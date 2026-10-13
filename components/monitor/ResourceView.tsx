'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useCallback,useEffect,useState} from 'react';
import {ArrowDown,ArrowUp,BatteryCharging,BatteryWarning} from 'lucide-react';
import {bytes,type AppGroup,type Snapshot} from '@/lib/telemetry';
import {ActivityChart,ChartLegend,type Series} from './ActivityChart';
import {AppsTable,sortApps,type AppSort} from './AppsTable';
import {palette} from './nav';
import {AnimatedNumber,Card,EmptyState,Gauge,Segmented} from './primitives';
import {rangeOptions,windowed,type Range} from './OverviewView';
import {EvidenceSheet,type EvidenceState} from './EvidenceSheet';
import {anomalyBands,anomalySchema,evidenceSchema,isScored,type AnomalyReport,type EvidenceMetric} from '@/lib/evidence';

export type CollectorGet=(path:string)=>Promise<unknown>;
const RANGE_SECONDS={'1m':60,'5m':300,'1h':3600} as const;

export type ResourceKind='cpu'|'memory'|'disk'|'network'|'battery';
const MB=1024**2;

function Stat({label,value}:{label:string,value:React.ReactNode}){
  return <div className="stat"><span>{label}</span><b>{value}</b></div>;
}

export function ResourceView({kind,snapshot,history,apps,range,onRange,onSelect,collectorGet}:{kind:ResourceKind,snapshot:Snapshot,history:Snapshot[],apps:AppGroup[],range:Range,onRange:(r:Range)=>void,onSelect:(a:AppGroup)=>void,collectorGet?:CollectorGet}){
  const [sort,setSort]=useState<AppSort>(kind==='memory'?'memory':'cpu');
  const [loaded,setAnomalies]=useState<AnomalyReport|null>(null);
  const [evidence,setEvidence]=useState<EvidenceState|null>(null);
  const metric=kind==='battery'?null:kind;
  const anomalies=collectorGet&&metric?loaded:null;
  const explainable=metric==='cpu'||metric==='memory'||metric==='network';

  // Anomaly bands come from the collector's stored history; demo data and imports have none.
  useEffect(()=>{
    if(!collectorGet||!metric)return;
    let live=true;
    const load=async()=>{
      const since=Math.floor(Date.now()/1000)-3600;
      const raw=await collectorGet(`/v1/anomalies?since=${since}&limit=900`);
      const parsed=anomalySchema.safeParse(raw);
      if(live)setAnomalies(parsed.success?parsed.data:null);
    };
    void load();
    const id=setInterval(load,15000);
    return()=>{live=false;clearInterval(id);};
  },[collectorGet,metric]);

  const explain=useCallback(async(from:number,to:number)=>{
    if(!collectorGet||!explainable)return;
    const request={from,to,metric:metric as EvidenceMetric};
    setEvidence({request,report:null,loading:true});
    const raw=await collectorGet(`/v1/evidence?from=${from/1000}&to=${to/1000}&metric=${request.metric}`);
    const parsed=evidenceSchema.safeParse(raw);
    setEvidence({request,report:parsed.success?parsed.data:null,loading:false});
  },[collectorGet,metric,explainable]);
  const series=windowed(history,snapshot,range);
  const memPct=snapshot.memoryUsed/snapshot.host.memoryTotal*100;
  const diskPct=snapshot.diskUsed/snapshot.diskTotal*100;
  const peak=(f:(s:Snapshot)=>number)=>Math.max(0,...series.map(f));
  const avg=(f:(s:Snapshot)=>number)=>series.length?series.reduce((n,s)=>n+f(s),0)/series.length:0;

  let chartSeries:Series[]=[];let data:({t:number}&Record<string,number>)[]=[];let domain:[number,number|'auto']=[0,100];let format=(v:number)=>`${v.toFixed(1)}%`;
  let hero:React.ReactNode=null;let stats:React.ReactNode=null;let note='';
  if(kind==='cpu'){
    chartSeries=[{key:'v',label:'CPU',color:palette.cpu}];data=series.map(s=>({t:Date.parse(s.timestamp),v:s.cpu}));
    hero=<Gauge value={snapshot.cpu} color={palette.cpu} size={148} stroke={14}><b><AnimatedNumber value={snapshot.cpu} decimals={1}/>%</b><span>in use</span></Gauge>;
    stats=<><Stat label="Logical cores" value={snapshot.host.cores}/><Stat label="Average" value={`${avg(s=>s.cpu).toFixed(1)}%`}/><Stat label="Peak" value={`${peak(s=>s.cpu).toFixed(1)}%`}/><Stat label="Processes" value={snapshot.processes.length}/></>;
  }else if(kind==='memory'){
    chartSeries=[{key:'v',label:'Memory',color:palette.memory}];data=series.map(s=>({t:Date.parse(s.timestamp),v:s.memoryUsed/s.host.memoryTotal*100}));
    hero=<Gauge value={memPct} color={palette.memory} size={148} stroke={14}><b><AnimatedNumber value={memPct}/>%</b><span>{bytes(snapshot.memoryUsed)}</span></Gauge>;
    stats=<><Stat label="Installed" value={bytes(snapshot.host.memoryTotal)}/><Stat label="In use" value={bytes(snapshot.memoryUsed)}/><Stat label="Available" value={bytes(snapshot.host.memoryTotal-snapshot.memoryUsed)}/><Stat label="Peak" value={`${peak(s=>s.memoryUsed/s.host.memoryTotal*100).toFixed(0)}%`}/></>;
    note='App memory is summed RSS and can double-count shared pages.';
  }else if(kind==='disk'){
    chartSeries=[{key:'v',label:'Disk',color:palette.disk}];data=series.map(s=>({t:Date.parse(s.timestamp),v:s.diskUsed/s.diskTotal*100}));
    hero=<Gauge value={diskPct} color={palette.disk} size={148} stroke={14}><b><AnimatedNumber value={diskPct}/>%</b><span>full</span></Gauge>;
    stats=<><Stat label="Capacity" value={bytes(snapshot.diskTotal)}/><Stat label="Used" value={bytes(snapshot.diskUsed)}/><Stat label="Free" value={bytes(snapshot.diskTotal-snapshot.diskUsed)}/></>;
    note='Root volume only. Per-app disk I/O is not collected in this release.';
  }else if(kind==='network'){
    chartSeries=[{key:'down',label:'Download',color:palette.network},{key:'up',label:'Upload',color:palette.upload}];
    data=series.map(s=>({t:Date.parse(s.timestamp),down:s.download/MB,up:s.upload/MB}));domain=[0,'auto'];format=v=>`${v.toFixed(1)} MB/s`;
    hero=<div className="net-hero"><div><ArrowDown size={20} style={{color:palette.network}}/><b><AnimatedNumber value={snapshot.download/MB} decimals={2}/></b><span>MB/s in</span></div><div><ArrowUp size={20} style={{color:palette.upload}}/><b><AnimatedNumber value={snapshot.upload/MB} decimals={2}/></b><span>MB/s out</span></div></div>;
    stats=<><Stat label="Peak in" value={`${bytes(peak(s=>s.download))}/s`}/><Stat label="Peak out" value={`${bytes(peak(s=>s.upload))}/s`}/><Stat label="Average in" value={`${bytes(avg(s=>s.download))}/s`}/></>;
    note='Totals across non-loopback interfaces. Per-app bandwidth is not collected in this release.';
  }else{
    if(snapshot.battery===null)return <Card><EmptyState icon={<BatteryWarning size={30}/>} title="No battery reading"><p>This host does not report a battery, or the collector cannot read it.</p></EmptyState></Card>;
    chartSeries=[{key:'v',label:'Battery',color:palette.battery}];data=series.map(s=>({t:Date.parse(s.timestamp),v:s.battery??0}));format=v=>`${v.toFixed(0)}%`;
    hero=<div className="battery-hero"><div className="battery-shell"><i style={{width:`${snapshot.battery}%`,background:snapshot.battery<20?'var(--danger)':palette.battery}}/></div><b><AnimatedNumber value={snapshot.battery}/>%</b><span><BatteryCharging size={14}/>Reported charge</span></div>;
  }

  return <div className="stack">
    <div className="resource-grid">
      <Card className="hero-card">{hero}{stats&&<div className="stats">{stats}</div>}</Card>
      <Card className="chart-card">
        <div className="section-bar"><div><h2>History</h2><ChartLegend series={chartSeries}/></div><Segmented label="Time range" value={range} onChange={onRange} options={rangeOptions}/></div>
        <ActivityChart data={data} series={chartSeries} domain={domain} format={format} bands={anomalyBands(anomalies,metric??'cpu')} onSelectRange={collectorGet&&explainable?r=>void explain(r.from,r.to):undefined}/>
        {collectorGet&&metric&&<div className="evidence-bar">
          <p className="fine-print">{anomalies===null?'Anomaly bands need a collector with /v1/anomalies.'
            :isScored(anomalies,metric)?'Shaded ranges are statistically unusual for this host.':'Learning this host’s normal; needs about five minutes of samples.'}
            {explainable&&' Drag across the chart to see what was busy.'}</p>
          {explainable&&<button type="button" className="button small" onClick={()=>{const end=Date.parse(snapshot.timestamp);void explain(end-RANGE_SECONDS[range]*1000,end);}}>What was busy in this range?</button>}
        </div>}
        {note&&<p className="fine-print">{note}</p>}
      </Card>
    </div>
    {(kind==='cpu'||kind==='memory')&&<Card>
      <div className="section-bar"><h2>{kind==='cpu'?'CPU by application':'Memory by application'}</h2></div>
      <AppsTable apps={sortApps(apps,sort)} memoryTotal={snapshot.host.memoryTotal} cores={snapshot.host.cores} sort={sort} onSort={setSort} onSelect={onSelect}/>
    </Card>}
    <EvidenceSheet state={evidence} onClose={()=>setEvidence(null)}/>
  </div>;
}
