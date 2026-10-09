'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useEffect,useMemo,useRef,useState} from 'react';
import {ShieldCheck} from 'lucide-react';
import {groupApps,macMajor,platformOf,runningContainers,type AppGroup,type Snapshot} from '@/lib/telemetry';
import {computeAlerts} from '@/lib/alerts';
import {useTelemetry} from '@/hooks/use-telemetry';
import {usePreferences,viewerPlatform,type Theme} from '@/hooks/use-preferences';
import {useIsMobile} from '@/hooks/use-mobile';
import {AppShell} from '@/components/monitor/AppShell';
import {MonitorSidebar} from '@/components/monitor/Sidebar';
import {Toolbar} from '@/components/monitor/Toolbar';
import {ClusterView} from '@/components/monitor/ClusterView';
import {OverviewView,type Range} from '@/components/monitor/OverviewView';
import {ResourceView,type ResourceKind} from '@/components/monitor/ResourceView';
import {AppsTable,sortApps,type AppSort} from '@/components/monitor/AppsTable';
import {ContainersView} from '@/components/monitor/ContainersView';
import {ProjectsView} from '@/components/monitor/ProjectsView';
import {AlertsView} from '@/components/monitor/AlertsView';
import {SettingsView} from '@/components/monitor/SettingsView';
import {ConnectDialog} from '@/components/monitor/ConnectDialog';
import {ProcessSheet} from '@/components/monitor/ProcessSheet';
import {Card} from '@/components/monitor/primitives';
import {views,type ViewId} from '@/components/monitor/nav';

function save(s:Snapshot){
  const url=URL.createObjectURL(new Blob([JSON.stringify(s,null,2)],{type:'application/json'}));
  const a=document.createElement('a');a.href=url;a.download='vytrix-snapshot.json';a.click();URL.revokeObjectURL(url);
}

const resourceViews:ViewId[]=['cpu','memory','disk','network','battery'];
const searchableViews:ViewId[]=['overview','cpu','memory','applications','containers','projects'];

export default function Page(){
  const telemetry=useTelemetry();
  const {snapshot,history,source,paused,setPaused,error,setError}=telemetry;
  const {prefs,update,dark}=usePreferences();
  const isMobile=useIsMobile();
  const [view,setView]=useState<ViewId>('overview');
  const [search,setSearch]=useState('');
  const [appSort,setAppSort]=useState<AppSort>('cpu');
  const [range,setRange]=useState<Range>('5m');
  const [selected,setSelected]=useState<AppGroup|null>(null);
  const [connectOpen,setConnectOpen]=useState(false);
  const [sidebarOpen,setSidebarOpen]=useState(true);
  const [mobileNav,setMobileNav]=useState(false);
  const [dismissed,setDismissed]=useState<string[]>([]);
  const file=useRef<HTMLInputElement>(null);

  const [viewer,setViewer]=useState<'macos'|'linux'|'other'>('macos');
  useEffect(()=>{const frame=requestAnimationFrame(()=>setViewer(viewerPlatform()));return()=>cancelAnimationFrame(frame);},[]);
  const host=platformOf(snapshot.host.os);
  const autoPlatform=source==='demo'?viewer:host;
  const theme:Theme=prefs.theme!=='auto'?prefs.theme:autoPlatform==='linux'?'adwaita':source!=='demo'&&macMajor(snapshot.host.os)>=27?'macos27':'glass';
  useEffect(()=>{document.documentElement.dataset.theme=theme;},[theme]);

  const allApps=useMemo(()=>groupApps(snapshot),[snapshot]);
  const apps=useMemo(()=>{const q=search.toLowerCase();return allApps.filter(a=>a.name.toLowerCase().includes(q)||(a.project??'').toLowerCase().includes(q));},[allApps,search]);
  const alerts=prefs.alertsEnabled?computeAlerts(snapshot,prefs.threshold).filter(a=>!dismissed.includes(a.id)):[];
  const meta=views.find(v=>v.id===view)!;

  useEffect(()=>{
    type Context={registerTool:(t:unknown,o:{signal:AbortSignal})=>unknown};
    const context=(document as unknown as {modelContext?:Context}).modelContext;
    if(!context)return;
    const controller=new AbortController();
    try{
      Promise.resolve(context.registerTool({name:'read_system_snapshot',description:'Read the displayed host telemetry (including Docker/Podman containers) and whether its source is demo, live or imported.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,untrustedContentHint:true},execute:(input:unknown)=>{if(!input||typeof input!=='object'||Object.keys(input).length)throw new Error('Expected empty object');return {source,snapshot};}},{signal:controller.signal})).catch(()=>{});
    }catch{}
    return()=>controller.abort();
  },[snapshot,source]);

  const navigate=(v:ViewId)=>{setView(v);setMobileNav(false);if(v==='memory')setAppSort('memory');if(v==='cpu')setAppSort('cpu');document.getElementById('content')?.scrollTo({top:0});};
  const openImport=()=>file.current?.click();
  const badges={alerts:alerts.length,containers:snapshot.containers?runningContainers(snapshot).length:0,applications:allApps.length};

  const sidebar=<MonitorSidebar view={view} onSelect={navigate} badges={badges} snapshot={snapshot} source={source} paused={paused}/>;
  const toolbar=<Toolbar monitorControls={view!=='cluster'} theme={theme} title={meta.label} subtitle={view==='overview'?`${snapshot.host.name} · ${snapshot.host.os}`:meta.subtitle} search={search} onSearch={setSearch} showSearch={searchableViews.includes(view)} paused={paused} onPause={()=>setPaused(!paused)} onExport={()=>save(snapshot)} onConnect={()=>{setError('');setConnectOpen(true);}} onToggleSidebar={()=>isMobile?setMobileNav(true):setSidebarOpen(o=>!o)} dark={dark} onToggleDark={()=>update('appearance',dark?'light':'dark')}/>;
  const footer=<footer className="statusbar">
    <span><ShieldCheck size={13}/>Read-only telemetry</span>
    <span>{view==='cluster'?'Cluster coordinator':source==='demo'?'Simulated data':source==='live'?'Live collector':'Imported snapshot'}{paused&&view!=='cluster'?' · Paused':''}</span>
    <span className="num" suppressHydrationWarning>{source==='demo'||view==='cluster'?'':new Date(snapshot.timestamp).toLocaleTimeString()}</span>
  </footer>;

  return <>
    <AppShell sidebar={sidebar} toolbar={toolbar} footer={footer} sidebarOpen={sidebarOpen} mobileNavOpen={mobileNav} onMobileNavChange={setMobileNav}>
      {source==='demo'&&view==='overview'&&<div className="banner"><span>You are viewing <b>simulated telemetry</b>. A web page cannot read local processes.</span><button type="button" className="button small primary" onClick={()=>setConnectOpen(true)}>Connect a collector</button></div>}
      {error&&!connectOpen&&<div className="banner error" role="alert">{error}</div>}
      {/* Mounted once and only hidden, so a cluster sign-in survives switching views (the token is in memory). */}
      <div className="view" hidden={view!=='cluster'}><ClusterView/></div>
      <div className="view" key={view} hidden={view==='cluster'}>
        {view==='overview'&&<OverviewView snapshot={snapshot} history={history} apps={apps} range={range} onRange={setRange} onNavigate={navigate} onSelect={setSelected}/>}
        {resourceViews.includes(view)&&<ResourceView kind={view as ResourceKind} snapshot={snapshot} history={history} apps={apps} range={range} onRange={setRange} onSelect={setSelected}/>}
        {view==='applications'&&<Card>
          <div className="section-bar"><div><h2>Applications <span className="count">{apps.length}</span></h2><p className="muted">{snapshot.processes.length} processes grouped by executable and app bundle</p></div></div>
          <AppsTable apps={sortApps(apps,appSort)} memoryTotal={snapshot.host.memoryTotal} cores={snapshot.host.cores} sort={appSort} onSort={setAppSort} onSelect={setSelected}/>
        </Card>}
        {view==='containers'&&<ContainersView snapshot={snapshot} search={search} host={source==='demo'?viewer:host}/>}
        {view==='projects'&&<ProjectsView projects={apps.filter(a=>a.project)} onSelect={setSelected}/>}
        {view==='alerts'&&<AlertsView alerts={alerts} enabled={prefs.alertsEnabled} threshold={prefs.threshold} onDismiss={id=>setDismissed(d=>[...d,id])} onConfigure={()=>navigate('settings')}/>}
        {view==='settings'&&<SettingsView prefs={prefs} update={(k,v)=>{if(k==='threshold')setDismissed([]);update(k,v);}} resolvedTheme={theme} source={source} onImport={openImport} onExport={()=>save(snapshot)} onUseDemo={telemetry.useDemo}/>}
      </div>
    </AppShell>
    <ConnectDialog open={connectOpen} onOpenChange={setConnectOpen} onConnect={telemetry.connect} onImport={openImport} error={error}/>
    <ProcessSheet app={selected} onClose={()=>setSelected(null)}/>
    <input ref={file} type="file" accept="application/json,.json" hidden onChange={e=>{const f=e.target.files?.[0];if(f)void telemetry.importFile(f);e.target.value='';}}/>
  </>;
}
