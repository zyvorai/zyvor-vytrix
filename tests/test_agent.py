# SPDX-License-Identifier: BUSL-1.1
import datetime as dt
import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
spec=importlib.util.spec_from_file_location('vytrix',Path(__file__).parents[1]/'agent/vytrix.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
class Tests(unittest.TestCase):
    def test_group_names(self):
        self.assertEqual(v.app_name('/Applications/Google Chrome.app/Contents/Frameworks/helper'),'Google Chrome')
        self.assertEqual(v.app_name('chrome-helper'),'Google Chrome')
    def test_real_snapshot(self):
        c=v.Collector();c.snapshot();s=c.snapshot()
        self.assertEqual(s['version'],1)
        self.assertGreater(s['host']['memoryTotal'],0)
        self.assertTrue(0<=s['cpu']<=100)
        self.assertLessEqual(s['memoryUsed'],s['host']['memoryTotal'])
        self.assertGreater(len(s['processes']),0)
        self.assertNotIn('cmdline',s['processes'][0])
    def test_api_auth_cors_history(self):
        with tempfile.TemporaryDirectory() as d:
            store=v.Store(str(Path(d)/'history.sqlite'))
            s=v.Collector().snapshot();store.add(s)
            server=v.TelemetryServer(('127.0.0.1',0),'a'*32,['https://example.com'],store,s)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            url='http://127.0.0.1:'+str(server.server_port)
            def get(path,token=None,origin=None):
                headers={}
                if token:headers['Authorization']='Bearer '+token
                if origin:headers['Origin']=origin
                return urllib.request.urlopen(urllib.request.Request(url+path,headers=headers),timeout=3)
            try:
                for token in (None,'wrong'):
                    with self.assertRaises(urllib.error.HTTPError) as e:get('/v1/snapshot',token)
                    self.assertEqual(e.exception.code,401)
                with get('/v1/snapshot','a'*32,'https://example.com') as r:
                    self.assertEqual(r.headers['Access-Control-Allow-Origin'],'https://example.com')
                    self.assertEqual(json.load(r)['version'],1)
                with self.assertRaises(urllib.error.HTTPError) as e:get('/v1/snapshot','a'*32,'https://evil.example')
                self.assertEqual(e.exception.code,403)
                with get('/v1/history?limit=1','a'*32) as r:self.assertEqual(len(json.load(r)['samples']),1)
                with self.assertRaises(urllib.error.HTTPError) as e:get('/v1/history?limit=1001','a'*32)
                self.assertEqual(e.exception.code,400)
                with self.assertRaises(urllib.error.HTTPError) as e:get('/v1/history?since=nan','a'*32)
                self.assertEqual(e.exception.code,400)
            finally:
                server.shutdown();server.server_close();thread.join()
    def test_healthz_and_ui_proxy(self):
        seen={}
        class Upstream(v.BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):
                seen['auth']=self.headers.get('Authorization');seen['proto']=self.headers.get('X-Forwarded-Proto')
                if self.path=='/old':
                    self.send_response(307);self.send_header('Location',upstream_url+'/new');self.send_header('Content-Length','0');self.end_headers();return
                body=b'<html>dashboard</html>'
                self.send_response(200);self.send_header('Content-Type','text/html');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
        upstream=v.ThreadingHTTPServer(('127.0.0.1',0),Upstream)
        upstream_url='http://127.0.0.1:'+str(upstream.server_port)
        with tempfile.TemporaryDirectory() as d:
            store=v.Store(str(Path(d)/'history.sqlite'))
            server=v.TelemetryServer(('127.0.0.1',0),'a'*32,[],store,{'version':1},upstream_url)
            threads=[threading.Thread(target=x.serve_forever,daemon=True) for x in (upstream,server)]
            for t in threads:t.start()
            url='http://127.0.0.1:'+str(server.server_port)
            opener=urllib.request.build_opener(v.NoRedirect)
            try:
                with urllib.request.urlopen(url+'/healthz',timeout=3) as r:self.assertEqual(json.load(r),{'status':'ok'})
                request=urllib.request.Request(url+'/',headers={'Authorization':'Bearer '+'a'*32})
                with urllib.request.urlopen(request,timeout=3) as r:self.assertEqual(r.read(),b'<html>dashboard</html>')
                self.assertIsNone(seen['auth'])
                self.assertEqual(seen['proto'],'http')
                with self.assertRaises(urllib.error.HTTPError) as e:opener.open(url+'/old',timeout=3)
                self.assertEqual(e.exception.code,307);self.assertEqual(e.exception.headers['Location'],'/new')
                with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(url+'/v1/snapshot',timeout=3)
                self.assertEqual(e.exception.code,401)
                upstream.shutdown();upstream.server_close()
                with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(url+'/',timeout=3)
                self.assertEqual(e.exception.code,502)
            finally:
                server.shutdown();server.server_close()
    def test_tls(self):
        import ssl,shutil,subprocess
        if not shutil.which('openssl'):self.skipTest('openssl not installed')
        with tempfile.TemporaryDirectory() as d:
            cert,key=str(Path(d)/'tls.crt'),str(Path(d)/'tls.key')
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=127.0.0.1','-keyout',key,'-out',cert],check=True,capture_output=True)
            store=v.Store(str(Path(d)/'history.sqlite'))
            server=v.TelemetryServer(('127.0.0.1',0),'a'*32,[],store,{'version':1})
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key)
            server.socket=context.wrap_socket(server.socket,server_side=True,do_handshake_on_connect=False)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            try:
                client=ssl.create_default_context(cafile=cert);client.check_hostname=False
                # Python 3.13+ verifies strictly by default; the bare self-signed cert this test makes (LibreSSL on macOS) has no CA basic constraint.
                client.verify_flags&=~getattr(ssl,'VERIFY_X509_STRICT',0)
                request=urllib.request.Request(f'https://127.0.0.1:{server.server_port}/v1/snapshot',headers={'Authorization':'Bearer '+'a'*32})
                with urllib.request.urlopen(request,timeout=3,context=client) as r:self.assertEqual(json.load(r)['version'],1)
            finally:
                server.shutdown();server.server_close();thread.join()
    @staticmethod
    def synthetic(n,cpu=lambda i:20.0,network=lambda i:1000.0):
        out=[]
        base=1_760_000_000
        for i in range(n):
            stamp=dt.datetime.fromtimestamp(base+i*2,dt.timezone.utc).isoformat().replace('+00:00','Z')
            out.append({'timestamp':stamp,'host':{'memoryTotal':1000},'cpu':cpu(i),'memoryUsed':400,
                        'diskUsed':500,'diskTotal':1000,'download':network(i),'upload':0})
        return out
    def test_anomaly_warmup_is_null_not_zero(self):
        report=v.anomaly_report(self.synthetic(v.ANOMALY_WARMUP))
        self.assertEqual(len(report['samples']),v.ANOMALY_WARMUP)
        self.assertTrue(all(row['cpu'] is None for row in report['samples']))
        self.assertEqual(report['rate']['cpu'],None)
        self.assertEqual(report['windows'],[])
    def test_anomaly_flat_signal_is_quiet(self):
        report=v.anomaly_report(self.synthetic(400,cpu=lambda i:20+(i%3)))
        self.assertEqual(report['windows'],[])
        self.assertEqual(report['rate']['cpu'],0.0)
    def test_anomaly_spike_becomes_one_window(self):
        spike=lambda i:95.0 if 300<=i<305 else 20.0
        report=v.anomaly_report(self.synthetic(400,cpu=spike))
        cpu=[w for w in report['windows'] if w['metric']=='cpu']
        self.assertEqual(len(cpu),1)
        self.assertEqual(cpu[0]['samples'],5)
        self.assertGreater(cpu[0]['peak'],v.ANOMALY_K)
        self.assertEqual([w for w in report['windows'] if w['metric']!='cpu'],[])
    def test_anomaly_small_wobble_below_floor_is_ignored(self):
        report=v.anomaly_report(self.synthetic(400,cpu=lambda i:22.0 if i>=300 else 20.0))
        self.assertEqual(report['windows'],[])
    def test_anomaly_since_only_trims_output(self):
        samples=self.synthetic(400,cpu=lambda i:95.0 if 300<=i<305 else 20.0)
        since=dt.datetime.fromisoformat(samples[290]['timestamp'].replace('Z','+00:00')).timestamp()
        report=v.anomaly_report(samples,since)
        self.assertEqual(len(report['samples']),110)
        self.assertEqual(len([w for w in report['windows'] if w['metric']=='cpu']),1)
    def test_anomalies_endpoint(self):
        with tempfile.TemporaryDirectory() as d:
            store=v.Store(str(Path(d)/'history.sqlite'))
            for sample in self.synthetic(200):store.add(sample)
            snapshot=v.Collector().snapshot()
            server=v.TelemetryServer(('127.0.0.1',0),'a'*32,[],store,snapshot)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            base='http://127.0.0.1:'+str(server.server_port)
            def get(path):
                return urllib.request.urlopen(urllib.request.Request(base+path,headers={'Authorization':'Bearer '+'a'*32}),timeout=3)
            try:
                with get('/v1/anomalies?limit=200') as r:body=json.load(r)
                self.assertEqual(body['version'],1)
                self.assertEqual(body['metrics'],['cpu','memory','disk','network'])
                self.assertEqual(len(body['samples']),200)
                self.assertIsNotNone(body['samples'][-1]['cpu'])
                with self.assertRaises(urllib.error.HTTPError) as e:get('/v1/anomalies?limit=0')
                self.assertEqual(e.exception.code,400)
                with self.assertRaises(urllib.error.HTTPError) as e:get('/v1/anomalies?since=nan')
                self.assertEqual(e.exception.code,400)
            finally:
                server.shutdown();server.server_close();thread.join()
    def test_retention(self):
        with tempfile.TemporaryDirectory() as d:
            store=v.Store(str(Path(d)/'history.sqlite'))
            s=v.Collector().snapshot();old=dict(s,timestamp='2000-01-01T00:00:00Z')
            store.add(old);store.add(s)
            self.assertEqual(len(store.history()),1)
if __name__=='__main__':unittest.main()
