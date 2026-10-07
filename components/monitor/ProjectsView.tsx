'use client';
// SPDX-License-Identifier: Apache-2.0
import {FolderCode} from 'lucide-react';
import {bytes,type AppGroup} from '@/lib/telemetry';
import {Card,EmptyState} from './primitives';

export function ProjectsView({projects,onSelect}:{projects:AppGroup[],onSelect:(a:AppGroup)=>void}){
  if(!projects.length)return <Card><EmptyState icon={<FolderCode size={28}/>} title="No project folders visible"><p>Project detection reads the working directory of node, python, go and cargo processes on Linux. Collector permissions may limit it; it is unavailable on macOS in this release.</p></EmptyState></Card>;
  return <div className="project-grid">{projects.map(a=><Card className="project-card" key={a.name}>
    <span className="project-icon"><FolderCode size={20}/></span>
    <h3>{a.project}</h3>
    <p className="muted">{a.name} · {a.processes.length} process{a.processes.length===1?'':'es'}</p>
    <div className="project-stats"><div><span>CPU</span><b>{a.cpu.toFixed(1)}%</b></div><div><span>Memory</span><b>{bytes(a.memory)}</b></div></div>
    <div className="chips">{a.ports.length?a.ports.map(p=><span key={p} className="chip mono">:{p}</span>):<span className="muted">No listening ports</span>}</div>
    <button type="button" className="button block" onClick={()=>onSelect(a)}>Inspect processes</button>
  </Card>)}</div>;
}
