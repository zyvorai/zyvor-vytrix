'use client';
// SPDX-License-Identifier: BUSL-1.1
import {Sheet,SheetContent,SheetDescription,SheetTitle} from '@/components/ui/sheet';
import {bytes} from '@/lib/telemetry';
import type {EvidenceMetric,EvidenceReport} from '@/lib/evidence';

export type EvidenceRequest={from:number,to:number,metric:EvidenceMetric};
export type EvidenceState={request:EvidenceRequest,report:EvidenceReport|null,loading:boolean};

const unit=(metric:EvidenceMetric,v:number)=>metric==='cpu'?`${v.toFixed(1)}%`:metric==='memory'?bytes(v):`${bytes(v)}/s`;
const pct=(v:number|null|undefined)=>v==null?'—':`${v.toFixed(1)}%`;
const time=(ms:number)=>new Date(ms).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',second:'2-digit'});
const title={cpu:'CPU',memory:'Memory',network:'Network'} as const;

function hostLine(metric:EvidenceMetric,report:EvidenceReport){
  const key=metric==='network'?'download':metric;
  const now=report.host[key],before=report.baselineHost?.[key];
  const fmt=(v:number|null|undefined)=>v==null?'—':metric==='cpu'||metric==='memory'?`${v.toFixed(1)}%`:`${bytes(v)}/s`;
  return {mean:fmt(now?.mean),peak:fmt(now?.peak),before:fmt(before?.mean)};
}

export function EvidenceSheet({state,onClose}:{state:EvidenceState|null,onClose:()=>void}){
  const req=state?.request,report=state?.report;
  return <Sheet open={!!state} onOpenChange={o=>{if(!o)onClose();}}>
    <SheetContent side="right" className="glass-sheet process-sheet evidence-sheet">
      {req&&<>
        <div className="sheet-head"><div>
          <SheetTitle className="sheet-title">What was busy: {title[req.metric]}</SheetTitle>
          <SheetDescription>{time(req.from)} to {time(req.to)}</SheetDescription>
        </div></div>
        {state.loading&&<p className="muted">Reading the collector history…</p>}
        {!state.loading&&!report&&<p className="muted" role="status">The collector did not answer. It may predate /v1/evidence, or the range holds no stored samples.</p>}
        {report&&<>
          {(()=>{const h=hostLine(req.metric,report);return <div className="sheet-stats">
            <div><span>Mean in range</span><b>{h.mean}</b></div>
            <div><span>Peak</span><b>{h.peak}</b></div>
            <div><span>Before the range</span><b>{h.before}</b></div>
          </div>;})()}
          <p className="fine-print">{report.window.samples} samples in range, {report.window.baselineSamples} in the range before it. App memory is RSS.</p>
          <h3 className="sheet-h">Applications</h3>
          {report.apps.length===0?<p className="muted">No per-application samples in this range.</p>:
            <table className="data-table compact"><thead><tr><th scope="col">Application</th><th scope="col" className="num">Mean</th><th scope="col" className="num">Peak</th><th scope="col" className="num">Change</th><th scope="col" className="num">Present</th></tr></thead>
              <tbody>{report.apps.map(a=><tr key={a.name}><td><span className="truncate" title={a.name}>{a.name}</span></td>
                <td className="num">{unit(req.metric,a.mean)}</td><td className="num">{a.peak==null?'—':unit(req.metric,a.peak)}</td>
                <td className="num">{a.delta==null?'new':`${a.delta>=0?'+':''}${unit(req.metric,a.delta)}`}</td>
                <td className="num">{a.present}/{a.samples}</td></tr>)}</tbody></table>}
          {report.containers.length>0&&<>
            <h3 className="sheet-h">Containers</h3>
            <table className="data-table compact"><thead><tr><th scope="col">Container</th><th scope="col" className="num">CPU mean</th><th scope="col" className="num">CPU peak</th><th scope="col" className="num">Memory peak</th></tr></thead>
              <tbody>{report.containers.map((c,i)=><tr key={`${c.runtime}-${c.name}-${i}`}><td><span className="truncate" title={c.image??''}>{c.name??'unnamed'}</span>{c.runtime&&<small>{c.runtime}</small>}</td>
                <td className="num">{pct(c.meanCpu)}</td><td className="num">{pct(c.peakCpu)}</td><td className="num">{c.peakMemory==null?'—':bytes(c.peakMemory)}</td></tr>)}</tbody></table>
          </>}
          <h3 className="sheet-h">Anomalies in range</h3>
          {report.anomalies.windows.length===0
            ?<p className="muted">{report.anomalies.scoredSamples===0?'The baseline was still warming up, so nothing was scored.':'No anomalous windows in this range.'}</p>
            :<ul className="evidence-list">{report.anomalies.windows.map((w,i)=><li key={i}><b>{w.metric}</b> {time(Date.parse(w.start))} to {time(Date.parse(w.end))}, peak score {w.peak.toFixed(1)}</li>)}</ul>}
          {report.notes.length>0&&<ul className="evidence-list notes">{report.notes.map((n,i)=><li key={i}>{n}</li>)}</ul>}
        </>}
      </>}
    </SheetContent>
  </Sheet>;
}
