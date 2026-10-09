# SPDX-License-Identifier: BUSL-1.1
"""Enterprise/fleet data plane primitives for Vytrix coordinator."""
from __future__ import annotations
import base64
import hashlib
import hmac
import json
import math
import sqlite3
import threading
import time
import urllib.request
from urllib.parse import urlsplit
from typing import Any

VALID_ROLES = {"viewer", "auditor", "editor", "admin"}
ROLE_LEVEL = {"viewer": 10, "auditor": 20, "editor": 30, "admin": 40}


def role_at_least(role: str, required: str) -> bool:
    return ROLE_LEVEL.get(role, 0) >= ROLE_LEVEL[required]


def _json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, allow_nan=False)


def verify_sso(secret: str, user: str, timestamp: str, signature: str, now: float | None = None, skew: int = 60) -> bool:
    if not secret or not user or len(user) > 128:
        return False
    try:
        stamp = int(timestamp)
    except ValueError:
        return False
    now = time.time() if now is None else now
    if abs(now - stamp) > skew:
        return False
    expected = hmac.new(secret.encode(), f"{user}\n{stamp}".encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


def entitlement_status(token: str | None, secret: str | None, now: float | None = None) -> dict[str, Any]:
    """HMAC entitlement scaffold for self-hosted commercial packaging.

    Token: base64url(JSON).hex-hmac. This is intentionally a packaging scaffold, not
    DRM: it does not change the rights granted by LICENSE.
    """
    community = {"plan": "community", "maxNodes": 3, "features": ["monitor", "cluster"], "valid": True}
    if not token or not secret:
        return community
    try:
        payload_b64, signature = token.split(".", 1)
        expected = hmac.new(secret.encode(), payload_b64.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature):
            return {**community, "valid": False, "error": "invalid-signature"}
        padding = "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + padding))
        if payload.get("exp") and float(payload["exp"]) < (time.time() if now is None else now):
            return {**community, "valid": False, "error": "expired"}
        return {"valid": True, **payload}
    except (ValueError, TypeError, json.JSONDecodeError):
        return {**community, "valid": False, "error": "malformed"}


class FleetStore:
    def __init__(self, db: sqlite3.Connection, retention_days: int = 90, clock=time.time):
        self.db, self.clock = db, clock
        self.retention_days = min(3650, max(1, int(retention_days)))
        self.lock = threading.RLock()
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS fleet_node_meta(
          node_id TEXT PRIMARY KEY, tags TEXT NOT NULL DEFAULT '[]', group_name TEXT, site TEXT,
          inventory TEXT, agent_health TEXT, updated REAL NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS fleet_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT, node_id TEXT NOT NULL, at REAL NOT NULL, payload TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS fleet_samples_node_at ON fleet_samples(node_id,at);
        CREATE TABLE IF NOT EXISTS fleet_alert_rules(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, metric TEXT NOT NULL, op TEXT NOT NULL,
          threshold REAL NOT NULL, severity TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, group_name TEXT);
        CREATE TABLE IF NOT EXISTS fleet_alert_events(
          id INTEGER PRIMARY KEY AUTOINCREMENT, rule_id INTEGER, node_id TEXT, opened REAL, last_seen REAL,
          closed REAL, status TEXT, value REAL, message TEXT);
        CREATE TABLE IF NOT EXISTS fleet_webhooks(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, url TEXT NOT NULL, secret TEXT, enabled INTEGER NOT NULL DEFAULT 1);
        ''')

    def expire(self):
        cutoff = self.clock() - self.retention_days * 86400
        self.db.execute("DELETE FROM fleet_samples WHERE at<?", (cutoff,))
        self.db.execute("DELETE FROM fleet_alert_events WHERE closed IS NOT NULL AND closed<?", (cutoff,))

    def node_meta(self, node_id: str) -> dict[str, Any]:
        row = self.db.execute("SELECT * FROM fleet_node_meta WHERE node_id=?", (node_id,)).fetchone()
        if not row:
            return {"tags": [], "group": None, "site": None, "inventory": None, "agentHealth": None}
        return {"tags": json.loads(row["tags"]), "group": row["group_name"], "site": row["site"],
                "inventory": json.loads(row["inventory"]) if row["inventory"] else None,
                "agentHealth": json.loads(row["agent_health"]) if row["agent_health"] else None}

    def set_meta(self, node_id: str, tags: list[str], group: str | None, site: str | None):
        tags = sorted({str(t)[:64] for t in tags if str(t).strip()})[:64]
        group = str(group)[:128] if group else None; site = str(site)[:128] if site else None
        self.db.execute('''INSERT INTO fleet_node_meta(node_id,tags,group_name,site,updated) VALUES(?,?,?,?,?)
          ON CONFLICT(node_id) DO UPDATE SET tags=excluded.tags,group_name=excluded.group_name,site=excluded.site,updated=excluded.updated''',
          (node_id, _json(tags), group, site, self.clock()))

    def record(self, node_id: str, snapshot: dict[str, Any]):
        at = self.clock(); self.expire()
        self.db.execute("INSERT INTO fleet_samples(node_id,at,payload) VALUES(?,?,?)", (node_id, at, _json(snapshot)))
        inventory, agent = snapshot.get("inventory"), snapshot.get("agent")
        self.db.execute('''INSERT INTO fleet_node_meta(node_id,inventory,agent_health,updated) VALUES(?,?,?,?)
          ON CONFLICT(node_id) DO UPDATE SET inventory=excluded.inventory,agent_health=excluded.agent_health,updated=excluded.updated''',
          (node_id, _json(inventory) if inventory is not None else None, _json(agent) if agent is not None else None, at))
        self.evaluate(node_id, snapshot)

    def history(self, node_id: str, since: float = 0, limit: int = 300) -> list[dict[str, Any]]:
        rows = self.db.execute("SELECT payload FROM fleet_samples WHERE node_id=? AND at>=? ORDER BY at DESC LIMIT ?",
                               (node_id, max(0, since), min(1000, max(1, limit)))).fetchall()
        return [json.loads(r[0]) for r in reversed(rows)]

    @staticmethod
    def metric(snapshot: dict[str, Any], name: str) -> float | None:
        if name in ("cpu", "download", "upload"):
            value = snapshot.get(name)
        elif name == "memoryPercent":
            total = float(snapshot.get("host", {}).get("memoryTotal") or 0); value = float(snapshot.get("memoryUsed") or 0) / total * 100 if total else None
        elif name == "diskPercent":
            total = float(snapshot.get("diskTotal") or 0); value = float(snapshot.get("diskUsed") or 0) / total * 100 if total else None
        elif name == "temperatureCelsius": value = (snapshot.get("hardware") or {}).get("temperatureCelsius")
        elif name == "powerWatts": value = (snapshot.get("hardware") or {}).get("powerWatts")
        elif name == "gpuPercent":
            values = [g.get("utilization") for g in (snapshot.get("hardware") or {}).get("gpus", []) if g.get("utilization") is not None]
            value = max(values) if values else None
        elif name == "agentFailures": value = (snapshot.get("agent") or {}).get("failures")
        else: value = None
        try:
            value = float(value) if value is not None else None
            return value if value is None or math.isfinite(value) else None
        except (TypeError, ValueError): return None

    def list_rules(self):
        return [dict(r) for r in self.db.execute("SELECT * FROM fleet_alert_rules ORDER BY id")]

    def set_rule(self, body: dict[str, Any]):
        name = str(body.get("name") or "")[:128]; metric = str(body.get("metric") or "")
        op = str(body.get("op") or ">="); severity = str(body.get("severity") or "warning")
        threshold = float(body.get("threshold"))
        if not name or metric not in {"cpu","memoryPercent","diskPercent","download","upload","temperatureCelsius","powerWatts","gpuPercent","agentFailures"}:
            raise ValueError("invalid alert rule")
        if op not in {">",">=","<","<="} or severity not in {"info","warning","critical"} or not math.isfinite(threshold):
            raise ValueError("invalid alert rule")
        rule_id = body.get("id")
        if rule_id:
            self.db.execute("UPDATE fleet_alert_rules SET name=?,metric=?,op=?,threshold=?,severity=?,enabled=?,group_name=? WHERE id=?",
                (name,metric,op,threshold,severity,1 if body.get("enabled",True) else 0,body.get("group"),int(rule_id)))
            return int(rule_id)
        cur = self.db.execute("INSERT INTO fleet_alert_rules(name,metric,op,threshold,severity,enabled,group_name) VALUES(?,?,?,?,?,?,?)",
            (name,metric,op,threshold,severity,1 if body.get("enabled",True) else 0,body.get("group")))
        return cur.lastrowid

    def evaluate(self, node_id: str, snapshot: dict[str, Any]):
        meta = self.node_meta(node_id); now = self.clock()
        compare = {">": lambda a,b:a>b, ">=":lambda a,b:a>=b, "<":lambda a,b:a<b, "<=":lambda a,b:a<=b}
        for rule in self.db.execute("SELECT * FROM fleet_alert_rules WHERE enabled=1"):
            if rule["group_name"] and rule["group_name"] != meta["group"]: continue
            value = self.metric(snapshot, rule["metric"])
            if value is None: continue
            active = compare[rule["op"]](value, rule["threshold"])
            open_event = self.db.execute("SELECT * FROM fleet_alert_events WHERE rule_id=? AND node_id=? AND status='open' ORDER BY id DESC LIMIT 1", (rule["id"],node_id)).fetchone()
            if active and open_event:
                self.db.execute("UPDATE fleet_alert_events SET last_seen=?,value=? WHERE id=?", (now,value,open_event["id"]))
            elif active:
                message = f"{rule['name']}: {rule['metric']} {value:.2f} {rule['op']} {rule['threshold']:.2f}"
                cur = self.db.execute("INSERT INTO fleet_alert_events(rule_id,node_id,opened,last_seen,status,value,message) VALUES(?,?,?,?,?,?,?)",
                                      (rule["id"],node_id,now,now,"open",value,message))
                self._emit({"type":"alert.open","id":cur.lastrowid,"node":node_id,"severity":rule["severity"],"message":message,"value":value})
            elif open_event:
                self.db.execute("UPDATE fleet_alert_events SET status='closed',closed=?,last_seen=?,value=? WHERE id=?", (now,now,value,open_event["id"]))
                self._emit({"type":"alert.closed","id":open_event["id"],"node":node_id,"message":open_event["message"],"value":value})

    def alerts(self, limit: int = 200):
        return [dict(r) for r in self.db.execute("SELECT * FROM fleet_alert_events ORDER BY id DESC LIMIT ?", (min(1000,max(1,limit)),))]

    def webhooks(self): return [dict(r) for r in self.db.execute("SELECT id,name,url,enabled FROM fleet_webhooks ORDER BY id")]

    def set_webhook(self, name: str, url: str, secret: str = ""):
        parsed = urlsplit(url)
        if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in {"127.0.0.1","localhost","::1"}):
            raise ValueError("webhooks require HTTPS")
        cur = self.db.execute("INSERT INTO fleet_webhooks(name,url,secret,enabled) VALUES(?,?,?,1)", (name[:128],url[:2048],secret[:256]))
        return cur.lastrowid

    def _emit(self, payload: dict[str, Any]):
        raw = _json(payload).encode()
        for row in self.db.execute("SELECT url,secret FROM fleet_webhooks WHERE enabled=1").fetchall():
            def send(url=row[0], secret=row[1]):
                headers={"Content-Type":"application/json","User-Agent":"Vytrix-Fleet/1"}
                if secret: headers["X-Vytrix-Signature"] = hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
                try: urllib.request.urlopen(urllib.request.Request(url,data=raw,headers=headers,method="POST"),timeout=3).read(1)
                except Exception: pass
            threading.Thread(target=send,daemon=True).start()

    def prometheus(self, nodes: list[dict[str, Any]]) -> str:
        lines=["# HELP vytrix_node_online Whether the node is online", "# TYPE vytrix_node_online gauge"]
        for node in nodes:
            nid=str(node["id"]).replace('"',''); snap=node.get("snapshot") or {}; label=f'node="{nid}"'
            lines.append(f"vytrix_node_online{{{label}}} {1 if node.get('online') else 0}")
            for metric in ("cpu","download","upload"):
                value=self.metric(snap,metric)
                if value is not None: lines.append(f"vytrix_{metric}{{{label}}} {value}")
            for metric,name in (("memoryPercent","memory_percent"),("diskPercent","disk_percent"),("gpuPercent","gpu_percent"),("temperatureCelsius","temperature_celsius"),("powerWatts","power_watts")):
                value=self.metric(snap,metric)
                if value is not None: lines.append(f"vytrix_{name}{{{label}}} {value}")
        return "\n".join(lines)+"\n"
