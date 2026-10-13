'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useEffect,useState} from 'react';
import {History} from 'lucide-react';
import {changesSchema,timelineSchema,type ChangesReport,type TimelineReport} from '@/lib/evidence';
import type {CollectorGet} from './ResourceView';
import {Card,EmptyState,Segmented} from './primitives';

const spans=[{value:'5m' as const,label:'5m'},{value:'15m' as const,label:'15m'},{value:'30m' as const,label:'30m'}];
type Span=(typeof spans)[number]['value'];
const SECONDS:Record<Span,number>={'5m':300,'15m':900,'30m':1800};
const time=(iso:string)=>new Date(iso).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',second:'2-digit'});
/** `alert|cpu|fired|critical` to words. */
function keyText(key:string){const [kind,subject,detail,severity]=key.split('|');return `${kind} ${subject} ${detail}${severity?` (${severity})`:''}`;}

function Group({title,items}:{title:string,items:string[]}){
  if(!items.length)return null;
  return <div className="change-group"><h4>{title}</h4><div className="chips">{items.map(i=><span key={i} className="chip">{i}</span>)}</div></div>;
}

export function TimelineView({collectorGet,threshold,onConnect}:{collectorGet?:CollectorGet,threshold:number,onConnect:()=>void}){
  const [span,setSpan]=useState<Span>('15m');
  const [timeline,setTimeline]=useState<TimelineReport|null>(null);
  const [changes,setChanges]=useState<ChangesReport|null>(null);
  const [state,setState]=useState<'loading'|'done'>('loading');

  useEffect(()=>{
    if(!collectorGet)return;
    let live=true;
    const load=async()=>{
      const end=Date.now()/1000,start=end-SECONDS[span];
      const [t,c]=await Promise.all([
        collectorGet(`/v1/timeline?from=${start}&to=${end}&threshold=${threshold}`),
        collectorGet(`/v1/changes?since=${start}&to=${end}`),
      ]);
      if(!live)return;
      const tp=timelineSchema.safeParse(t),cp=changesSchema.safeParse(c);
      setTimeline(tp.success?tp.data:null);setChanges(cp.success?cp.data:null);setState('done');
    };
    void load();
    return()=>{live=false;};
  },[collectorGet,span,threshold]);

  if(!collectorGet)return <Card><EmptyState icon={<History size={30}/>} title="Timeline needs a collector">
    <p>The timeline replays the collector’s stored history. Demo data and imported snapshots have none.</p>
    <button type="button" className="button primary" onClick={onConnect}>Connect a collector</button>
  </EmptyState></Card>;

  const c=changes?.changes;
  return <div className="stack">
    <Card>
      <div className="section-bar"><div><h2>Incident timeline</h2><p className="muted">Alert transitions at {threshold}%, anomaly windows and container changes, replayed from stored history.</p></div>
        <Segmented label="Window" value={span} onChange={setSpan} options={spans}/></div>
      {state==='loading'&&!timeline&&<p className="muted">Reading the collector history…</p>}
      {state==='done'&&!timeline&&<p className="muted" role="status">The collector did not answer. It may predate /v1/timeline.</p>}
      {timeline&&<>
        <p className="fingerprint">Fingerprint <code>{timeline.fingerprint}</code> · {timeline.eventCount} event{timeline.eventCount===1?'':'s'} in {timeline.window.samples} samples</p>
        {timeline.events.length===0
          ?<p className="muted">Nothing happened in this window: no alert fired, no anomaly, no container change.</p>
          :<ol className="timeline-list">{timeline.events.map((e,i)=><li key={i} className={`timeline-row ${e.kind} ${e.severity}`}>
            <time dateTime={e.time}>{time(e.time)}</time><span className="timeline-kind">{e.kind}</span><span>{e.text}</span></li>)}</ol>}
        {timeline.whyChanged&&(timeline.whyChanged.newSincePrevious.length>0||timeline.whyChanged.goneSincePrevious.length>0)&&<div className="why-changed">
          <h3>Why this differs from the window before</h3>
          <Group title="New" items={timeline.whyChanged.newSincePrevious.map(keyText)}/>
          <Group title="Gone" items={timeline.whyChanged.goneSincePrevious.map(keyText)}/>
          <p className="fine-print">Previous fingerprint {timeline.whyChanged.previousFingerprint}.</p>
        </div>}
        {timeline.notes.map((n,i)=><p key={i} className="fine-print">{n}</p>)}
      </>}
    </Card>
    <Card>
      <div className="section-bar"><div><h2>What changed</h2><p className="muted">First against last sample in the window.</p></div></div>
      {changes&&!c&&<p className="muted">Fewer than two samples in this window; nothing to compare.</p>}
      {c&&<>
        {Object.values({a:c.appsStarted,b:c.appsStopped,c:c.portsOpened,d:c.portsClosed,e:c.containersAppeared,f:c.containersGone,g:c.containersChanged,h:c.transient.apps,i:c.transient.ports,j:c.transient.containers}).every(x=>x.length===0)&&<p className="muted">No apps, ports or containers appeared or went away.</p>}
        <Group title="Apps started" items={c.appsStarted}/>
        <Group title="Apps stopped" items={c.appsStopped}/>
        <Group title="Ports opened" items={c.portsOpened.map(p=>`${p.port} · ${p.app}`)}/>
        <Group title="Ports closed" items={c.portsClosed.map(p=>`${p.port} · ${p.app}`)}/>
        <Group title="Containers appeared" items={c.containersAppeared}/>
        <Group title="Containers gone" items={c.containersGone}/>
        <Group title="Containers changed" items={c.containersChanged.map(x=>`${x.container}: ${x.from??'?'} to ${x.to??'?'}`)}/>
        <Group title="Came and went inside the window" items={[...c.transient.apps,...c.transient.ports.map(p=>`${p.port} · ${p.app}`),...c.transient.containers]}/>
        {changes?.notes.map((n,i)=><p key={i} className="fine-print">{n}</p>)}
      </>}
    </Card>
  </div>;
}
