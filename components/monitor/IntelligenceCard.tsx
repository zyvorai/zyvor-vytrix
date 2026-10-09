'use client';
// SPDX-License-Identifier: BUSL-1.1
import {BrainCircuit,Flame,Gauge,Microchip,Network,Zap} from 'lucide-react';
import {bytes,type Snapshot} from '@/lib/telemetry';
import {Card,Meter} from './primitives';

export function IntelligenceCard({snapshot}:{snapshot:Snapshot}){
  const h=snapshot.hardware;
  const workloads=snapshot.aiWorkloads??[];
  if(!h&&!workloads.length)return null;
  const gpus=h?.gpus??[];
  const gpu=gpus.find(g=>g.utilization!==undefined)??gpus[0];
  const disk=workloads.reduce((n,w)=>n+w.diskReadRate+w.diskWriteRate,0);
  return <Card className="intelligence-card">
    <div className="section-bar"><div><h2><Microchip size={18}/> Silicon & AI</h2><p className="muted">Capability-based read-only telemetry. Unavailable counters are never estimated.</p></div></div>
    <div className="mini-containers">
      {gpu&&<div className="mini-container"><Gauge size={18}/><div><strong>{gpu.name}</strong><small>{gpu.backend??'GPU'}</small></div><b className="num">{gpu.utilization===undefined?'Available':`${gpu.utilization.toFixed(1)}%`}</b></div>}
      {h?.ane?.available&&<div className="mini-container"><BrainCircuit size={18}/><div><strong>Apple Neural Engine</strong><small>Core ML accelerator</small></div><b className="num">{h.ane.utilization===null?'Available':`${h.ane.utilization?.toFixed(1)}%`}</b></div>}
      {h?.temperatureCelsius!==undefined&&<div className="mini-container"><Flame size={18}/><div><strong>Thermal</strong><small>Highest readable sensor</small></div><b className="num">{h.temperatureCelsius.toFixed(1)} °C</b></div>}
      {h?.powerWatts!==undefined&&<div className="mini-container"><Zap size={18}/><div><strong>Power</strong><small>Readable supply draw</small></div><b className="num">{h.powerWatts.toFixed(1)} W</b></div>}
      {workloads.length>0&&<div className="mini-container"><BrainCircuit size={18}/><div><strong>{workloads.length} AI workload{workloads.length===1?'':'s'}</strong><small>{workloads.map(w=>w.engine).slice(0,3).join(' · ')}</small></div><b className="num">{workloads.reduce((n,w)=>n+w.cpu,0).toFixed(1)}% CPU</b></div>}
      {disk>0&&<div className="mini-container"><Network size={18}/><div><strong>AI storage traffic</strong><small>Read + write throughput</small></div><b className="num">{bytes(disk)}/s</b></div>}
    </div>
    {gpu?.utilization!==undefined&&<Meter value={gpu.utilization} label={`${gpu.name} utilization`}/>} 
  </Card>;
}
