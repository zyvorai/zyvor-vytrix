'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useState} from 'react';
import {ArrowDown,ArrowUp,Box,Terminal} from 'lucide-react';
import {bytes,formatPort,runtimeNames,type Container,type Snapshot} from '@/lib/telemetry';
import {Card,EmptyState,Meter,Segmented} from './primitives';
import {palette} from './nav';

type Filter='all'|'running'|'stopped';
const runtimeLabel={docker:'Docker',podman:'Podman'};

function ContainerCard({c,cores}:{c:Container,cores:number}){
  const running=c.state==='running';
  const memPct=c.memoryLimit?c.memory/c.memoryLimit*100:0;
  return <Card className={`container-card${running?'':' stopped'}`}>
    <div className="container-head">
      <span className={`runtime-badge ${c.runtime}`}>{runtimeLabel[c.runtime]}</span>
      <span className={`state-pill ${running?'running':c.state==='paused'?'paused':'stopped'}`}><i/>{c.state}</span>
    </div>
    <h3 title={c.name}>{c.name}</h3>
    <p className="mono image" title={c.image}>{c.image}</p>
    <div className="container-metrics">
      <div><div className="row"><span>CPU</span><b className="num">{c.cpu.toFixed(1)}%</b></div><Meter value={c.cpu/Math.max(1,cores)} color={palette.cpu} label={`${c.name} CPU`}/></div>
      <div><div className="row"><span>Memory</span><b className="num">{bytes(c.memory)}{c.memoryLimit?<small> / {bytes(c.memoryLimit)}</small>:null}</b></div><Meter value={c.memoryLimit?memPct:0} color={memPct>85?'var(--danger)':palette.memory} label={`${c.name} memory`}/></div>
    </div>
    <div className="container-foot">
      <span title="Received since start"><ArrowDown size={13}/>{bytes(c.netIn)}</span>
      <span title="Sent since start"><ArrowUp size={13}/>{bytes(c.netOut)}</span>
      <span className="mono id" title={c.id}>{c.id.slice(0,12)}</span>
    </div>
    {c.ports.length>0&&<div className="chips">{c.ports.slice(0,6).map(p=><span className="chip mono" key={formatPort(p)}>{formatPort(p)}</span>)}{c.ports.length>6&&<span className="chip">+{c.ports.length-6}</span>}</div>}
  </Card>;
}

export function ContainersView({snapshot,search,host}:{snapshot:Snapshot,search:string,host:'macos'|'linux'|'other'}){
  const [filter,setFilter]=useState<Filter>('all');
  const containers=snapshot.containers;
  const runtimes=snapshot.runtimes??[];
  if(containers===undefined)return <Card><EmptyState icon={<Box size={28}/>} title="No container data in this snapshot">
    <p>This snapshot was produced by a collector without container support, or with <code>--no-containers</code>. Update the collector to see Docker and Podman workloads.</p>
  </EmptyState></Card>;
  const q=search.toLowerCase();
  const visible=containers.filter(c=>(filter==='all'||(filter==='running')===(c.state==='running'))&&(c.name.toLowerCase().includes(q)||c.image.toLowerCase().includes(q)));
  const running=containers.filter(c=>c.state==='running');
  const cpu=running.reduce((n,c)=>n+c.cpu,0);
  const memory=running.reduce((n,c)=>n+c.memory,0);
  return <div className="stack">
    <div className="runtime-strip">
      {runtimeNames.map(name=>{const r=runtimes.find(x=>x.name===name);const count=containers.filter(c=>c.runtime===name).length;return <Card key={name} className="runtime-card">
        <span className={`runtime-badge ${name}`}>{runtimeLabel[name]}</span>
        <div><strong>{r?.available?`${count} container${count===1?'':'s'}`:r?.error??'Unknown'}</strong><span>{r?.available?`${containers.filter(c=>c.runtime===name&&c.state==='running').length} running`:name==='podman'?'brew install podman · dnf install podman':'Docker Desktop · apt install docker.io'}</span></div>
        <span className={`dot ${r?.available?'ok':'off'}`} aria-label={r?.available?'Available':'Unavailable'}/>
      </Card>;})}
      <Card className="runtime-card summary">
        <div><strong>{running.length} running</strong><span>{cpu.toFixed(1)}% CPU · {bytes(memory)}</span></div>
      </Card>
    </div>
    {host==='macos'&&<p className="fine-print">On macOS, Docker Desktop and Podman run containers inside a Linux VM. CPU and memory are relative to that VM, not the Mac.</p>}
    <div className="section-bar">
      <h2>Containers <span className="count">{visible.length}</span></h2>
      <Segmented label="Filter containers" value={filter} onChange={setFilter} options={[{value:'all',label:'All'},{value:'running',label:'Running'},{value:'stopped',label:'Stopped'}]}/>
    </div>
    {visible.length?runtimeNames.filter(r=>visible.some(c=>c.runtime===r)).map(r=><div key={r} className="stack-sm">
      <h3 className="group-title">{runtimeLabel[r]}</h3>
      <div className="container-grid">{visible.filter(c=>c.runtime===r).map(c=><ContainerCard key={`${c.runtime}-${c.id}`} c={c} cores={snapshot.host.cores}/>)}</div>
    </div>):<Card><EmptyState icon={<Terminal size={28}/>} title={containers.length?'No containers match':'No containers found'}>
      {containers.length?<p>Try a different search or filter.</p>:<p>Start one to see it here, for example <code>podman run -d -p 8080:80 nginx:alpine</code>.</p>}
    </EmptyState></Card>}
  </div>;
}
