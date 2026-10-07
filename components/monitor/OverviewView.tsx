'use client';
// SPDX-License-Identifier: Apache-2.0
import {useState} from 'react';
import {BatteryMedium,Box,ChevronRight,Cpu,HardDrive,Layers,MemoryStick,Network} from 'lucide-react';
import {bytes,groupApps,runningContainers,type AppGroup,type Snapshot} from '@/lib/telemetry';
import {ActivityChart,ChartLegend} from './ActivityChart';
import {AppsTable,sortApps,type AppSort} from './AppsTable';
import {MetricTile,type Metric} from './MetricTile';
import {palette,type ViewId} from './nav';
import {AppIcon,Card,Meter,Segmented} from './primitives';

export type Range='1m'|'5m'|'1h';
export const rangeOptions=[{value:'1m' as const,label:'1m'},{value:'5m' as const,label:'5m'},{value:'1h' as const,label:'1h'}];
export function windowed(history:Snapshot[],latest:Snapshot,range:Range){
  const seconds=range==='1m'?60:range==='5m'?300:3600;
  const end=Date.parse(latest.timestamp);
  return history.filter(s=>Date.parse(s.timestamp)>=end-seconds*1000);
}
const memPct=(s:Snapshot)=>s.memoryUsed/s.host.memoryTotal*100;
const diskPct=(s:Snapshot)=>s.diskUsed/s.diskTotal*100;
const MB=1024**2;

export function buildMetrics(snapshot:Snapshot,history:Snapshot[]):Metric[]{
  const apps=groupApps(snapshot);
  const running=runningContainers(snapshot);
  const peakNet=Math.max(1,...history.map(s=>s.download/MB));
  const metrics:Metric[]=[
    {id:'cpu',label:'CPU',icon:Cpu,value:snapshot.cpu,decimals:1,unit:'%',hint:`${snapshot.host.cores} logical cores`,color:palette.cpu,values:history.map(s=>s.cpu),gauge:snapshot.cpu},
    {id:'memory',label:'Memory',icon:MemoryStick,value:snapshot.memoryUsed/1024**3,decimals:1,unit:'GB',hint:`of ${bytes(snapshot.host.memoryTotal)}`,color:palette.memory,values:history.map(memPct),gauge:memPct(snapshot)},
    {id:'disk',label:'Disk',icon:HardDrive,value:diskPct(snapshot),unit:'%',hint:`${bytes(snapshot.diskTotal-snapshot.diskUsed)} free`,color:palette.disk,values:history.map(diskPct),gauge:diskPct(snapshot)},
    {id:'network',label:'Network',icon:Network,value:snapshot.download/MB,decimals:1,unit:'MB/s',hint:`↑ ${bytes(snapshot.upload)}/s out`,color:palette.network,values:history.map(s=>s.download/MB),sparkMax:peakNet},
  ];
  if(snapshot.battery!==null)metrics.push({id:'battery',label:'Battery',icon:BatteryMedium,value:snapshot.battery,unit:'%',hint:'Reported charge',color:palette.battery,values:history.map(s=>s.battery??0),gauge:snapshot.battery});
  else metrics.push({id:'applications',label:'Applications',icon:Layers,value:apps.length,unit:'apps',hint:`${snapshot.processes.length} processes`,color:palette.apps,values:history.map(s=>groupApps(s).length),sparkMax:Math.max(10,...history.map(s=>groupApps(s).length))});
  metrics.push({id:'containers',label:'Containers',icon:Box,value:snapshot.containers?running.length:null,unit:'running',hint:snapshot.containers?`${snapshot.containers.length} total`:'No container data',color:palette.containers,values:history.map(s=>runningContainers(s).length),sparkMax:Math.max(4,...history.map(s=>runningContainers(s).length))});
  return metrics;
}

export function OverviewView({snapshot,history,apps,range,onRange,onNavigate,onSelect}:{snapshot:Snapshot,history:Snapshot[],apps:AppGroup[],range:Range,onRange:(r:Range)=>void,onNavigate:(v:ViewId)=>void,onSelect:(a:AppGroup)=>void}){
  const [sort,setSort]=useState<AppSort>('cpu');
  const [leader,setLeader]=useState<'cpu'|'memory'>('cpu');
  const series=windowed(history,snapshot,range);
  const data=series.map(s=>({t:Date.parse(s.timestamp),cpu:s.cpu,memory:memPct(s)}));
  const top=sortApps(apps,leader).slice(0,5);
  const topMax=Math.max(1e-9,...top.map(a=>leader==='cpu'?a.cpu:a.memory));
  const running=runningContainers(snapshot).sort((a,b)=>b.cpu-a.cpu).slice(0,4);
  return <div className="stack">
    <div className="metric-grid">{buildMetrics(snapshot,series).map(m=><MetricTile key={m.id} metric={m} onClick={()=>onNavigate(m.id as ViewId)}/>)}</div>
    <div className="split-grid">
      <Card className="chart-card">
        <div className="section-bar"><div><h2>Activity</h2><ChartLegend series={[{key:'cpu',label:'CPU',color:palette.cpu},{key:'memory',label:'Memory',color:palette.memory}]}/></div><Segmented label="Time range" value={range} onChange={onRange} options={rangeOptions}/></div>
        <ActivityChart data={data} series={[{key:'cpu',label:'CPU',color:palette.cpu},{key:'memory',label:'Memory',color:palette.memory}]}/>
      </Card>
      <Card className="leader-card">
        <div className="section-bar"><h2>Top consumers</h2><Segmented label="Rank by" value={leader} onChange={setLeader} options={[{value:'cpu',label:'CPU'},{value:'memory',label:'Memory'}]}/></div>
        <ol className="leader-list">{top.map(a=><li key={a.name}><button type="button" onClick={()=>onSelect(a)}>
          <AppIcon name={a.name} size={28}/>
          <div className="leader-text"><div className="row"><strong>{a.name}</strong><b className="num">{leader==='cpu'?`${a.cpu.toFixed(1)}%`:bytes(a.memory)}</b></div>
          <Meter value={(leader==='cpu'?a.cpu:a.memory)/topMax*100} color={leader==='cpu'?palette.cpu:palette.memory} label={`${a.name} relative ${leader}`}/></div>
        </button></li>)}</ol>
      </Card>
    </div>
    {running.length>0&&<Card>
      <div className="section-bar"><h2>Running containers</h2><button type="button" className="link-button" onClick={()=>onNavigate('containers')}>View all<ChevronRight size={15}/></button></div>
      <div className="mini-containers">{running.map(c=><div key={`${c.runtime}-${c.id}`} className="mini-container">
        <span className={`runtime-dot ${c.runtime}`}/>
        <div><strong>{c.name}</strong><small className="mono">{c.image}</small></div>
        <b className="num">{c.cpu.toFixed(1)}%</b><span className="num muted">{bytes(c.memory)}</span>
      </div>)}</div>
    </Card>}
    <Card>
      <div className="section-bar"><div><h2>Applications <span className="count">{apps.length}</span></h2><p className="muted">{snapshot.processes.length} processes grouped by application</p></div><button type="button" className="link-button" onClick={()=>onNavigate('applications')}>Show all<ChevronRight size={15}/></button></div>
      <AppsTable apps={sortApps(apps,sort).slice(0,8)} memoryTotal={snapshot.host.memoryTotal} cores={snapshot.host.cores} sort={sort} onSort={setSort} onSelect={onSelect}/>
    </Card>
  </div>;
}
