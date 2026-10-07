'use client';
// SPDX-License-Identifier: Apache-2.0
import {AlertTriangle,ShieldCheck} from 'lucide-react';
import {type Alert} from '@/lib/alerts';
import {Card,EmptyState} from './primitives';

export function AlertsView({alerts,enabled,threshold,onDismiss,onConfigure}:{alerts:Alert[],enabled:boolean,threshold:number,onDismiss:(id:string)=>void,onConfigure:()=>void}){
  return <div className="stack">
    <Card className="alerts-card">
      <div className="section-bar"><div><h2>Threshold alerts</h2><p className="muted">{enabled?`Checks CPU, memory, disk and container limits against ${threshold}%. Dismissals last for this session.`:'Alerts are turned off.'}</p></div><button type="button" className="button" onClick={onConfigure}>Configure</button></div>
      {alerts.length?<ul className="alert-list">{alerts.map(a=><li key={a.id} className={`alert-row ${a.severity}`}>
        <span className="alert-icon"><AlertTriangle size={18}/></span>
        <div><h3>{a.title}</h3><p>{a.text}</p></div>
        <button type="button" className="button small" onClick={()=>onDismiss(a.id)}>Dismiss</button>
      </li>)}</ul>:<EmptyState icon={<ShieldCheck size={30}/>} title="All clear"><p>Current readings are below the threshold, or alerts are disabled or dismissed.</p></EmptyState>}
    </Card>
  </div>;
}
