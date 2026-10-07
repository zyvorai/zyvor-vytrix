'use client';
// SPDX-License-Identifier: Apache-2.0
import {Sheet,SheetContent,SheetDescription,SheetTitle} from '@/components/ui/sheet';
import {bytes,type AppGroup} from '@/lib/telemetry';
import {AppIcon} from './primitives';

export function ProcessSheet({app,onClose}:{app:AppGroup|null,onClose:()=>void}){
  const processes=app?[...app.processes].sort((a,b)=>b.cpu-a.cpu):[];
  return <Sheet open={!!app} onOpenChange={o=>{if(!o)onClose();}}>
    <SheetContent side="right" className="glass-sheet process-sheet">
      {app&&<>
        <div className="sheet-head">
          <AppIcon name={app.name} size={44}/>
          <div><SheetTitle className="sheet-title">{app.name}</SheetTitle><SheetDescription>{app.project?`Project ${app.project}`:'Application group'}</SheetDescription></div>
        </div>
        <div className="sheet-stats">
          <div><span>Processes</span><b>{app.processes.length}</b></div>
          <div><span>CPU</span><b>{app.cpu.toFixed(1)}%</b></div>
          <div><span>Memory</span><b>{bytes(app.memory)}</b></div>
        </div>
        <p className="fine-print">One full logical core = 100% CPU. Memory is summed RSS and may double-count shared pages.</p>
        <div className="sheet-list">
          <table className="data-table compact">
            <thead><tr><th scope="col">PID</th><th scope="col">Process</th><th scope="col" className="num">CPU</th><th scope="col" className="num">Memory</th></tr></thead>
            <tbody>{processes.map(p=><tr key={p.pid}><td className="mono muted">{p.pid}</td><td><span className="truncate" title={p.name}>{p.name}</span>{p.ports.length>0&&<small className="mono">:{p.ports.join(', :')}</small>}</td><td className="num">{p.cpu.toFixed(1)}%</td><td className="num">{bytes(p.memory)}</td></tr>)}</tbody>
          </table>
        </div>
      </>}
    </SheetContent>
  </Sheet>;
}
