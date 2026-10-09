# SPDX-License-Identifier: BUSL-1.1
import base64, hashlib, hmac, importlib.util, json, sqlite3, tempfile, time, unittest
from pathlib import Path
ROOT=Path(__file__).parents[1]
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
fleet=load('fleet_probe_test',ROOT/'agent/fleet.py');core=load('fleet_core_test',ROOT/'cluster/fleet_core.py')

class FleetTests(unittest.TestCase):
 def test_nettop_parser(self):
  raw='pid,bytes_in,bytes_out\n42,1000,2000\n42,50,70\n7,3,4\n'
  self.assertEqual(fleet.parse_nettop_csv(raw)[42],(1050,2070))
  self.assertEqual(fleet.parse_nettop_csv('bad,header\n1,2'),{})
 def test_update_checksum(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'candidate';p.write_bytes(b'hello');sha=hashlib.sha256(b'hello').hexdigest()
   self.assertTrue(fleet.verify_update_manifest({'sha256':sha},p));self.assertFalse(fleet.verify_update_manifest({'sha256':'0'*64},p))
 def test_sso_and_entitlement(self):
  now=1000;sig=hmac.new(b'secret',b'alice\n1000',hashlib.sha256).hexdigest()
  self.assertTrue(core.verify_sso('secret','alice','1000',sig,now));self.assertFalse(core.verify_sso('secret','alice','800',sig,now))
  payload={'plan':'business','maxNodes':25,'features':['fleet'],'exp':2000};raw=base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=');token=raw+'.'+hmac.new(b'key',raw.encode(),hashlib.sha256).hexdigest()
  status=core.entitlement_status(token,'key',now);self.assertTrue(status['valid']);self.assertEqual(status['maxNodes'],25)
 def test_store_alert_history_meta_prometheus(self):
  db=sqlite3.connect(':memory:');db.row_factory=sqlite3.Row;clock=[1000.0];store=core.FleetStore(db,90,lambda:clock[0])
  store.set_meta('n1',['prod','ai'],'inference','pune');self.assertEqual(store.node_meta('n1')['tags'],['ai','prod'])
  rid=store.set_rule({'name':'Hot CPU','metric':'cpu','op':'>=','threshold':90,'severity':'critical','enabled':True});self.assertGreater(rid,0)
  sample={'cpu':95,'download':1,'upload':2,'host':{'memoryTotal':100},'memoryUsed':50,'diskTotal':100,'diskUsed':20,'hardware':{'gpus':[{'utilization':80}]},'agent':{'failures':0},'inventory':{'agentVersion':'0.4.0'}}
  store.record('n1',sample);self.assertEqual(store.alerts()[0]['status'],'open');self.assertEqual(len(store.history('n1')),1)
  clock[0]+=10;sample['cpu']=10;store.record('n1',sample);self.assertEqual(store.alerts()[0]['status'],'closed')
  text=store.prometheus([{'id':'n1','online':True,'snapshot':sample}]);self.assertIn('vytrix_node_online{node="n1"} 1',text);self.assertIn('vytrix_cpu{node="n1"} 10.0',text)
 def test_roles(self):
  self.assertTrue(core.role_at_least('editor','auditor'));self.assertFalse(core.role_at_least('viewer','editor'))

if __name__=='__main__':unittest.main()
