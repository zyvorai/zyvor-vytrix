'use client';
// SPDX-License-Identifier: BUSL-1.1
import {ChevronRight} from 'lucide-react';
import {bytes,type AppGroup} from '@/lib/telemetry';
import {AppIcon,Meter} from './primitives';
import {palette} from './nav';

export type AppSort='cpu'|'memory'|'name';

export function sortApps(apps:AppGroup[],sort:AppSort){
  return [...apps].sort((a,b)=>sort==='memory'?b.memory-a.memory:sort==='name'?a.name.localeCompare(b.name):b.cpu-a.cpu);
}

export function AppsTable({apps,memoryTotal,cores,sort,onSort,onSelect,emptyText='No applications match your search.'}:{apps:AppGroup[],memoryTotal:number,cores:number,sort:AppSort,onSort:(s:AppSort)=>void,onSelect:(a:AppGroup)=>void,emptyText?:string}){
  const header=(key:AppSort,label:string)=><button type="button" className="th-sort" data-active={sort===key} onClick={()=>onSort(key)}>{label}{sort===key&&<span aria-hidden="true">{key==='name'?' ↑':' ↓'}</span>}</button>;
  return <div className="table-wrap">
    <table className="data-table">
      <thead><tr>
        <th scope="col">{header('name','Application')}</th>
        <th scope="col" className="num">Processes</th>
        <th scope="col">{header('cpu','CPU')}</th>
        <th scope="col">{header('memory','Memory')}</th>
        <th scope="col">Ports</th>
        <th scope="col"><span className="sr-only">Inspect</span></th>
      </tr></thead>
      <tbody>{apps.map(a=><tr key={a.name} onClick={()=>onSelect(a)}>
        <td><div className="app-cell"><AppIcon name={a.name}/><div><strong>{a.name}</strong><small>{a.project?`Project · ${a.project}`:`${a.processes.length} process${a.processes.length===1?'':'es'}`}</small></div></div></td>
        <td className="num">{a.processes.length}</td>
        <td><div className="meter-cell"><span className="num">{a.cpu.toFixed(1)}%</span><Meter value={a.cpu/Math.max(1,cores)} color={palette.cpu} label={`${a.name} CPU`}/></div></td>
        <td><div className="meter-cell"><span className="num">{bytes(a.memory)}</span><Meter value={a.memory/memoryTotal*100} color={palette.memory} label={`${a.name} memory`}/></div></td>
        <td>{a.ports.length?<div className="chips">{a.ports.slice(0,4).map(p=><span key={p} className="chip mono">{p}</span>)}{a.ports.length>4&&<span className="chip">+{a.ports.length-4}</span>}</div>:<span className="muted">—</span>}</td>
        <td className="row-action"><button type="button" className="icon-button ghost" aria-label={`Inspect ${a.name}`} onClick={e=>{e.stopPropagation();onSelect(a);}}><ChevronRight size={16}/></button></td>
      </tr>)}</tbody>
    </table>
    {apps.length===0&&<p className="table-empty">{emptyText}</p>}
  </div>;
}
