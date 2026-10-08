'use client';
// SPDX-License-Identifier: Apache-2.0
import {useCallback,useEffect,useRef,useState} from 'react';
import {Monitor,ShieldCheck,Server} from 'lucide-react';
import {clusterOrigin,clusterRequest,clusterSchema,sessionSchema,pairingSchema,auditSchema,demoCluster,type ClusterSnapshot} from '@/lib/cluster';
import {bytes,groupApps,type Snapshot} from '@/lib/telemetry';
import {Card,Meter,Sparkline} from './primitives';

type Connection={origin:string,token:string};
/** Read-only fleet view: the coordinator only receives telemetry, so there is nothing here that changes a Mac. */
export function ClusterView(){
  const [cluster,setCluster]=useState<ClusterSnapshot>(demoCluster);
  const [connection,setConnection]=useState<Connection|null>(null);
  const [origin,setOrigin]=useState('http://127.0.0.1:9848');
  const [username,setUsername]=useState('');
  const [password,setPassword]=useState('');
  const [credential,setCredential]=useState('');
  const [error,setError]=useState('');
  const [busy,setBusy]=useState(false);
  const [failed,setFailed]=useState(false);
  const [detail,setDetail]=useState<string|null>(null);
  const [name,setName]=useState('');
  const [pairing,setPairing]=useState<{code:string,expires:number}|null>(null);
  const [audit,setAudit]=useState<{id:number,at:number,actor:string,event:string}[]>([]);
  const [query,setQuery]=useState('');
  const [histories,setHistories]=useState<Record<string,Snapshot[]>>({});
  const generation=useRef(0);
  const active=useRef<Connection|null>(null);
  const refresh=useCallback(async(c:Connection)=>clusterSchema.parse(await clusterRequest(c.origin,'/v1/cluster',c.token)),[]);
  useEffect(()=>{
    if(!connection)return;
    let mounted=true,polling=false;
    const poll=async()=>{if(polling)return;polling=true;try{const next=await refresh(connection);if(mounted){setCluster(next);setFailed(false);setError(e=>e.startsWith('Coordinator unavailable')?'':e);setHistories(h=>Object.fromEntries(next.nodes.filter(n=>n.snapshot).map(n=>[n.id,[...(h[n.id]??[]),n.snapshot!].slice(-60)])));}}catch{if(mounted){setFailed(true);setError('Coordinator unavailable or session expired. Last readings are shown.');}}finally{polling=false;}};
    const interval=setInterval(poll,2000);
    return()=>{mounted=false;clearInterval(interval);};
  },[connection,refresh]);
  const signIn=async()=>{
    const attempt=++generation.current;
    setBusy(true);setError('');
    try{
      const base=clusterOrigin(origin);
      const token=credential.trim()||sessionSchema.parse(await clusterRequest(base,'/v1/login','',{username,password})).token;
      const c={origin:base,token};const next=await refresh(c);
      if(generation.current!==attempt)return;
      active.current=c;setConnection(c);setCluster(next);setDetail(null);setHistories({});setFailed(false);setCredential('');setPassword('');setPairing(null);setAudit([]);
    }catch(e){if(generation.current===attempt)setError(e instanceof Error?e.message:'Could not connect');}finally{if(generation.current===attempt)setBusy(false);}
  };
  const signOut=()=>{
    generation.current++;const c=active.current;active.current=null;
    if(c)void clusterRequest(c.origin,'/v1/logout',c.token,{}).catch(()=>{});
    setConnection(null);setCluster(demoCluster());setHistories({});setDetail(null);setPairing(null);setAudit([]);setError('');setFailed(false);setBusy(false);
  };
  const pair=async()=>{if(!connection)return;const c=connection;setBusy(true);setError('');try{const result=await clusterRequest(c.origin,'/v1/pairings',c.token,{name});if(active.current===c)setPairing(pairingSchema.parse(result));}catch(e){if(active.current===c)setError(e instanceof Error?e.message:'Pairing failed');}finally{if(active.current===c)setBusy(false);}};
  const focused=cluster.nodes.find(n=>n.id===detail);
  const revoke=async()=>{if(!connection||!focused||!window.confirm(`Revoke ${focused.name}? It must enroll again to send telemetry.`))return;const c=connection;setBusy(true);try{await clusterRequest(c.origin,'/v1/revoke',c.token,{node:focused.id});const next=await refresh(c);if(active.current===c){setCluster(next);setDetail(null);}}catch(e){if(active.current===c)setError(e instanceof Error?e.message:'Revoke failed');}finally{if(active.current===c)setBusy(false);}};
  const inspect=async()=>{if(!connection)return;const c=connection;try{const result=await clusterRequest(c.origin,'/v1/audit',c.token);if(active.current===c)setAudit(auditSchema.parse(result).events);}catch{if(active.current===c)setError('Could not load audit history');}};
  const healthy=cluster.nodes.filter(n=>n.online&&!failed);
  const totalMemory=healthy.reduce((sum,n)=>sum+(n.snapshot?.host.memoryTotal??0),0);
  return <div className="cluster-view">
    <div className="section-bar"><div><h2><Server size={20}/> Mac cluster</h2><p className="muted">Read-only readings from every Mac that reports to your coordinator.</p></div>{connection&&<button className="button" onClick={signOut}>Sign out</button>}</div>
    {!connection?<Card className="cluster-connect"><div><h3>Connect your cluster</h3><p className="muted">The machines below show demonstration data. Sign in to your coordinator, or paste a session token.</p></div><form onSubmit={e=>{e.preventDefault();void signIn();}}>
      <label>Coordinator URL<input value={origin} onChange={e=>setOrigin(e.target.value)} required type="url"/></label>
      <label>Username<input value={username} onChange={e=>setUsername(e.target.value)} autoComplete="username"/></label>
      <label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} autoComplete="current-password"/></label>
      <label>Session token (optional)<input type="password" value={credential} onChange={e=>setCredential(e.target.value)} autoComplete="off"/></label>
      <button className="button primary" disabled={busy}>{busy?'Connecting…':'Sign in'}</button>
    </form></Card>:<div className="banner"><ShieldCheck size={18}/><span>{cluster.actor} · {cluster.role} · Tokens stay in tab memory</span></div>}
    {error&&<div className="banner error" role="alert">{error}</div>}
    <div className="cluster-summary"><Card><strong>{healthy.length} / {cluster.nodes.length}</strong><span>Machines online</span></Card><Card><strong>{healthy.reduce((s,n)=>s+(n.snapshot?.host.cores??0),0)}</strong><span>CPU cores online</span></Card><Card><strong>{bytes(totalMemory)}</strong><span>Memory across online hosts</span></Card></div>
    <div className="cluster-actions"><label>Find a machine<input type="search" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Machine name"/></label></div>
    <div className="cluster-grid">{cluster.nodes.filter(n=>n.name.toLowerCase().includes(query.toLowerCase())).map(n=><Card key={n.id} className="machine-card">
      <div className="machine-heading"><Monitor size={28}/><div><h3>{n.name}</h3><span className="muted">{n.snapshot?.host.os??'Waiting for first sample'}</span></div></div>
      <div className={`machine-status ${n.online&&!failed?'online':''}`}>{n.online&&!failed?'Online':'Offline / stale'}{connection&&n.seen>0?` · ${new Date(n.seen*1000).toLocaleTimeString()}`:''}</div>
      {n.snapshot&&<><div className="machine-metric"><span>CPU</span><b>{n.snapshot.cpu.toFixed(1)}%</b></div><Meter value={n.snapshot.cpu} label={`${n.name} CPU`}/><Sparkline values={(histories[n.id]??[n.snapshot]).map(s=>s.cpu)} color="var(--chart-cpu)"/><div className="machine-metric"><span>Memory</span><b>{bytes(n.snapshot.memoryUsed)} / {bytes(n.snapshot.host.memoryTotal)}</b></div><Meter value={n.snapshot.memoryUsed/n.snapshot.host.memoryTotal*100} label={`${n.name} memory`}/><div className="machine-metric"><span>Disk</span><b>{bytes(n.snapshot.diskUsed)} / {bytes(n.snapshot.diskTotal)}</b></div><div className="machine-metric"><span>Network ↓ / ↑</span><b>{bytes(n.snapshot.download)}/s / {bytes(n.snapshot.upload)}/s</b></div></>}
      <button className="button small" onClick={()=>setDetail(n.id)}>Inspect {n.name}</button>
    </Card>)}</div>
    {cluster.nodes.length===0&&<Card><p>No machines enrolled. Create a pairing code and run the worker on your Mac.</p></Card>}
    {focused&&<Card className="cluster-detail"><div className="section-bar"><h3>{focused.name} · Machine details</h3><div className="button-row">{connection&&cluster.role==='admin'&&<button className="button small" disabled={busy} onClick={()=>void revoke()}>Revoke this Mac</button>}<button className="button small" onClick={()=>setDetail(null)}>Close details</button></div></div><p className="muted">{focused.id} · GPU and sensors are not collected.</p>{focused.snapshot&&<><h4>Applications</h4><div className="table-scroll"><table className="data-table"><thead><tr><th>Application</th><th>CPU (one core = 100%)</th><th>Memory (RSS)</th></tr></thead><tbody>{groupApps(focused.snapshot).sort((a,b)=>b.cpu-a.cpu).slice(0,30).map(a=><tr key={a.name}><td>{a.name}</td><td>{a.cpu.toFixed(1)}%</td><td>{bytes(a.memory)}</td></tr>)}</tbody></table></div><h4>Containers</h4>{(focused.snapshot.containers??[]).map(c=><p key={`${c.runtime}-${c.id}`}>{c.name} · {c.runtime} · {c.state} · {bytes(c.memory)}</p>)}</>}</Card>}
    {connection&&cluster.role==='admin'&&<Card className="cluster-enrollment"><h3>Join another Mac</h3><p className="muted">Pairing codes expire after five minutes and can be used once. They only let a Mac send telemetry to this coordinator.</p><div className="cluster-actions"><label>Machine name<input value={name} onChange={e=>setName(e.target.value)} maxLength={128}/></label><button className="button primary" disabled={busy||!name.trim()} onClick={()=>void pair()}>Create pairing code</button><button className="button" onClick={()=>void inspect()}>Load audit history</button></div>{pairing&&<div><p>Private pairing code: <code>{pairing.code}</code></p><p className="muted">Expires {new Date(pairing.expires*1000).toLocaleTimeString()}. Enter it at the worker’s enrollment prompt.</p></div>}{audit.map(a=><p key={a.id}>{new Date(a.at*1000).toLocaleString()} · {a.actor} · {a.event}</p>)}</Card>}
  </div>;
}
