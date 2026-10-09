'use client';
// SPDX-License-Identifier: BUSL-1.1
import {Monitor} from 'lucide-react';
import {sections,views,type ViewId} from './nav';
import {type Snapshot} from '@/lib/telemetry';
import {type Source} from '@/hooks/use-telemetry';

const sourceLabel={demo:'Demo data',live:'Live collector',import:'Imported snapshot'};

export function MonitorSidebar({view,onSelect,badges,snapshot,source,paused}:{view:ViewId,onSelect:(v:ViewId)=>void,badges:Partial<Record<ViewId,number>>,snapshot:Snapshot,source:Source,paused:boolean}){
  return <nav className="sidebar-inner" aria-label="Monitor sections">
    <div className="brand"><span className="brand-mark" aria-hidden="true"/><span>zyvor<b>Vytrix</b></span></div>
    {sections.map(section=><div className="nav-section" key={section}>
      <div className="nav-heading">{section}</div>
      <ul>{views.filter(v=>v.section===section).map(v=>{const Icon=v.icon;const badge=badges[v.id];return <li key={v.id}>
        <button type="button" className="nav-item" aria-current={view===v.id?'page':undefined} onClick={()=>onSelect(v.id)}>
          <Icon size={16} strokeWidth={2}/><span>{v.label}</span>{badge?<span className={`nav-badge ${v.id==='alerts'?'danger':''}`}>{badge}</span>:null}
        </button>
      </li>;})}</ul>
    </div>)}
    <div className="host-card">
      <div className="host-card-icon"><Monitor size={16}/></div>
      <div className="host-card-text">
        <strong title={snapshot.host.name}>{view==='cluster'?'Mac cluster':snapshot.host.name}</strong>
        <span>{view==='cluster'?'Read-only fleet view':snapshot.host.os}</span>
      </div>
      <div className={`status-pill ${source}${paused?' paused':''}`}><i/>{view==='cluster'?'Coordinator':paused?'Paused':sourceLabel[source]}</div>
    </div>
  </nav>;
}
