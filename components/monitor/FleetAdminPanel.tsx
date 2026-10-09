'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useEffect,useState} from 'react';
import type {ClusterSnapshot} from '@/lib/cluster';
import {addWebhook,getAlerts,getRules,saveRule,setNodeMeta,alertRuleSchema} from '@/lib/fleet';
import {Card} from './primitives';
import {z} from 'zod';
type Rule=z.infer<typeof alertRuleSchema>;
type Connection={origin:string,token:string};
export function FleetAdminPanel({cluster,connection}:{cluster:ClusterSnapshot,connection:Connection|null}){
 const [rules,setRules]=useState<Rule[]>([]),[alerts,setAlerts]=useState<any[]>([]),[error,setError]=useState('');
 const [node,setNode]=useState(cluster.nodes[0]?.id??''),[tags,setTags]=useState(''),[group,setGroup]=useState(''),[site,setSite]=useState('');
 const canAudit=cluster.role!=='viewer',canOperate=cluster.role==='operator'||cluster.role==='admin';
 useEffect(()=>{if(!connection||!canAudit)return;void Promise.all([getRules(connection.origin,connection.token),getAlerts(connection.origin,connection.token)]).then(([r,a])=>{setRules(r);setAlerts(a)}).catch(e=>setError(String(e)));},[connection,canAudit]);
 if(!connection)return null;
 return <Card><div className="section-bar"><div><h3>Fleet Pro</h3><p className="muted">Tags, groups, retention, centralized alerts and enterprise telemetry.</p></div><span className="count">{cluster.entitlement?.plan??'community'}</span></div>
  {error&&<p role="alert">{error}</p>}
  <div className="cluster-summary"><div><strong>{cluster.nodes.filter(n=>n.online).length}</strong><span>online</span></div><div><strong>{alerts.filter(a=>a.status==='open').length}</strong><span>open alerts</span></div><div><strong>{rules.filter(r=>r.enabled!==false).length}</strong><span>alert rules</span></div></div>
  {canOperate&&<><h4>Machine metadata</h4><div className="cluster-actions"><select value={node} onChange={e=>setNode(e.target.value)}>{cluster.nodes.map(n=><option key={n.id} value={n.id}>{n.name}</option>)}</select><input placeholder="tags: ai,prod" value={tags} onChange={e=>setTags(e.target.value)}/><input placeholder="group" value={group} onChange={e=>setGroup(e.target.value)}/><input placeholder="site" value={site} onChange={e=>setSite(e.target.value)}/><button className="button" onClick={()=>void setNodeMeta(connection.origin,connection.token,node,tags.split(',').map(x=>x.trim()).filter(Boolean),group||null,site||null).catch(e=>setError(String(e)))}>Save</button></div>
  <h4>Quick alert</h4><button className="button" onClick={()=>void saveRule(connection.origin,connection.token,{name:'High CPU',metric:'cpu',op:'>=',threshold:90,severity:'critical',enabled:true}).then(()=>getRules(connection.origin,connection.token).then(setRules)).catch(e=>setError(String(e)))}>Add CPU ≥ 90% rule</button></>}
  {cluster.role==='admin'&&<><h4>Webhook</h4><button className="button" onClick={()=>{const url=window.prompt('HTTPS webhook URL');if(url)void addWebhook(connection.origin,connection.token,'Fleet alerts',url,'').catch(e=>setError(String(e)))}}>Add webhook</button></>}
  {canAudit&&alerts.length>0&&<><h4>Recent alerts</h4>{alerts.slice(0,8).map(a=><p key={a.id}><b>{a.status}</b> · {a.node_id} · {a.message}</p>)}</>}
 </Card>;
}
