#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Vytrix production fleet coordinator wrapper.

Extends the existing coordinator without modifying it: longer history, metadata/tags,
alerts/webhooks, scoped roles, signed SSO-proxy login, metrics export and entitlements.
"""
from __future__ import annotations
import argparse, getpass, importlib.util, json, os, ssl, sys, time, secrets
from pathlib import Path
from http.server import ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

HERE=Path(__file__).resolve().parent

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    if spec is None or spec.loader is None: raise RuntimeError(f"Cannot load {path}")
    m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m

base=load("vytrix_coordinator_base",HERE/"coordinator.py")
core=load("vytrix_fleet_core",HERE/"fleet_core.py")

class FleetCluster(base.Cluster):
    def __init__(self,database,users,retention_days=90,clock=time.time,sso_secret="",license_token="",license_secret=""):
        self.enterprise_users={k:{**v,"role":v.get("role","viewer")} for k,v in users.items()}
        normalized={k:{**v,"role":"admin" if v.get("role")=="admin" else "viewer"} for k,v in users.items()}
        super().__init__(database,normalized,clock)
        self.fleet=core.FleetStore(self.db,retention_days,clock)
        self.sso_secret=sso_secret
        self.entitlement=core.entitlement_status(license_token,license_secret,clock())
        for user in self.enterprise_users.values():
            if user.get("role") not in core.VALID_ROLES: raise ValueError("role must be viewer/auditor/editor/admin")

    def principal(self,token):
        actor,_=super().principal(token)
        return actor,self.enterprise_users[actor]

    def login(self,username,password,address):
        result=super().login(username,password,address);result["role"]=self.enterprise_users[username]["role"];return result

    def sso_login(self,user,timestamp,signature,address):
        if not core.verify_sso(self.sso_secret,user,timestamp,signature,self.clock()): raise base.APIError(401,"Invalid SSO assertion")
        config=self.enterprise_users.get(user)
        if not config: raise base.APIError(403,"SSO user not provisioned")
        token=secrets.token_urlsafe(32); self.db.execute("INSERT INTO sessions VALUES(?,?,?)",(base.digest(token),user,self.clock()+base.SESSION_TTL))
        self.audit(user,"sso-login",{"address":address});return {"token":token,"expires":self.clock()+base.SESSION_TTL,"actor":user,"role":config["role"]}

    def nodes(self,user):
        rows=super().nodes(user)
        for row in rows: row.update(self.fleet.node_meta(row["id"]))
        return rows

    def enroll(self,code):
        maximum=int(self.entitlement.get("maxNodes") or 3)
        active=self.db.execute("SELECT COUNT(*) FROM nodes WHERE revoked=0").fetchone()[0]
        if active>=maximum: raise base.APIError(402,f"Plan allows {maximum} nodes")
        return super().enroll(code)

    def heartbeat(self,token,body):
        node=self.node(token); result=super().heartbeat(token,body); self.fleet.record(node["id"],body["snapshot"]); return result

    def _require(self,user,role):
        if not core.role_at_least(user.get("role","viewer"),role): raise base.APIError(403,f"{role.title()} role required")

    def route(self,method,path,token,body,address):
        if method=="POST" and path=="/v1/sso":
            return self.sso_login(body.get("user",""),body.get("timestamp",""),body.get("signature",""),address)
        actor,user=self.principal(token) if path not in ("/v1/login","/v1/enroll","/v1/heartbeat") else (None,None)
        if method=="GET" and path=="/v1/cluster":
            return {"version":1,"actor":actor,"role":user["role"],"nodes":self.nodes(user),"entitlement":self.entitlement}
        if method=="GET" and path=="/v1/fleet/alerts": self._require(user,"auditor"); return {"events":self.fleet.alerts()}
        if method=="GET" and path=="/v1/fleet/rules": self._require(user,"auditor"); return {"rules":self.fleet.list_rules()}
        if method=="POST" and path=="/v1/fleet/rules": self._require(user,"editor"); return {"id":self.fleet.set_rule(body)}
        if method=="GET" and path=="/v1/fleet/webhooks": self._require(user,"admin"); return {"webhooks":self.fleet.webhooks()}
        if method=="POST" and path=="/v1/fleet/webhooks": self._require(user,"admin"); return {"id":self.fleet.set_webhook(str(body.get("name") or "Webhook"),str(body.get("url") or ""),str(body.get("secret") or ""))}
        if method=="POST" and path=="/v1/fleet/meta":
            self._require(user,"editor");node_id=base.text(body.get("node"));
            if not self.allowed(user,node_id): raise base.APIError(403,"Machine outside your permissions")
            self.fleet.set_meta(node_id,body.get("tags") or [],body.get("group"),body.get("site"));self.audit(actor,"node-meta-updated",{"node":node_id});return {"ok":True}
        if method=="GET" and path=="/v1/fleet/history":
            self._require(user,"viewer");node_id=base.text(body.get("node") if body else "") if body else ""
            if not node_id: raise base.APIError(400,"node query required")
            if not self.allowed(user,node_id): raise base.APIError(403,"Machine outside your permissions")
            return {"samples":self.fleet.history(node_id)}
        if method=="GET" and path=="/v1/fleet/entitlement": self._require(user,"viewer"); return self.entitlement
        return super().route(method,path,token,body,address)

class FleetServer(ThreadingHTTPServer):
    daemon_threads=True
    def __init__(self,address,cluster,origins,metrics_token=""):
        super().__init__(address,FleetHandler);self.cluster=cluster;self.origins=set(origins);self.metrics_token=metrics_token

class FleetHandler(base.Handler):
    def handle_api(self,method):
        try:
            origin=self.headers.get("Origin")
            if origin is not None and origin not in self.server.origins: raise base.APIError(403,"Origin denied")
            split=urlsplit(self.path);path=split.path
            if method=="GET" and path=="/healthz": return self.reply(200,{"status":"ok","fleet":True})
            if method=="GET" and path=="/metrics":
                token=self.headers.get("Authorization","").removeprefix("Bearer ")
                if not self.server.metrics_token or not secrets.compare_digest(token,self.server.metrics_token): raise base.APIError(401,"Unauthorized")
                users=next(iter(self.server.cluster.enterprise_users.values()),{"nodes":["*"]});nodes=self.server.cluster.nodes(users)
                raw=self.server.cluster.fleet.prometheus(nodes).encode();self.send_response(200);self.send_header("Content-Type","text/plain; version=0.0.4");self.send_header("Content-Length",str(len(raw)));self.end_headers();self.wfile.write(raw);return
            body={}
            if method=="POST":
                size=int(self.headers.get("Content-Length","0"));
                if not 0<size<=base.MAX_BODY: raise base.APIError(413,"Body exceeds limit or is empty")
                body=json.loads(self.rfile.read(size));
                if not isinstance(body,dict): raise base.APIError(400,"Expected JSON object")
            elif path=="/v1/fleet/history":
                query=parse_qs(split.query); body={"node":query.get("node",[""])[0]}
            token=self.headers.get("Authorization","").removeprefix("Bearer ")
            result=self.server.cluster.dispatch(method,path,token,body,self.client_address[0]);self.reply(200,result)
        except base.APIError as e:self.reply(e.status,{"error":e.message})
        except (ValueError,TypeError,KeyError):self.reply(400,{"error":"Invalid request"})
        except Exception:self.reply(500,{"error":"Coordinator error"})

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("--init-user");p.add_argument("--role",choices=sorted(core.VALID_ROLES),default="admin");p.add_argument("--config");p.add_argument("--database",default="cluster.sqlite");p.add_argument("--bind",default="127.0.0.1");p.add_argument("--port",type=int,default=9848);p.add_argument("--allow-origin",action="append",default=[]);p.add_argument("--tls-cert");p.add_argument("--tls-key");p.add_argument("--retention-days",type=int,default=int(os.environ.get("VYTRIX_RETENTION_DAYS","90")));args=p.parse_args()
    if args.init_user:
        print(json.dumps({args.init_user:{"password":base.password_hash(getpass.getpass("Password (12+ characters): ")),"role":args.role,"nodes":["*"]}},indent=2));return
    if not args.config:p.error("--config required")
    if bool(args.tls_cert)!=bool(args.tls_key) or (args.bind not in ("127.0.0.1","::1","localhost") and not args.tls_cert):p.error("Remote listener requires TLS")
    os.umask(0o077);config=Path(args.config)
    if config.stat().st_mode & 0o077:p.error("Config permissions must be 0600")
    cluster=FleetCluster(args.database,json.loads(config.read_text()),args.retention_days,sso_secret=os.environ.get("VYTRIX_SSO_SECRET",""),license_token=os.environ.get("VYTRIX_LICENSE_TOKEN",""),license_secret=os.environ.get("VYTRIX_LICENSE_SECRET",""));os.chmod(args.database,0o600)
    server=FleetServer((args.bind,args.port),cluster,args.allow_origin,os.environ.get("VYTRIX_METRICS_TOKEN",""))
    if args.tls_cert:
        ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ssl.TLSVersion.TLSv1_2;ctx.load_cert_chain(args.tls_cert,args.tls_key);server.socket=ctx.wrap_socket(server.socket,server_side=True)
    print(f"Vytrix fleet coordinator on {args.bind}:{args.port}",flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close();cluster.db.close()

if __name__=="__main__":main()
