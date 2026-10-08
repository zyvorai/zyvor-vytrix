'use client';
// SPDX-License-Identifier: Apache-2.0
import {Download,Moon,PanelLeft,Pause,Play,Plug,Search,Sun,X} from 'lucide-react';
import {type Theme} from '@/hooks/use-preferences';

function TrafficLights(){
  return <div className="traffic-lights" aria-hidden="true"><i className="close"/><i className="minimize"/><i className="zoom"/></div>;
}

function GnomeControls(){
  return <div className="gnome-controls" aria-hidden="true"><i><X size={12} strokeWidth={2.5}/></i></div>;
}

export function Toolbar({theme,title,subtitle,search,onSearch,showSearch,paused,onPause,onExport,onConnect,onToggleSidebar,dark,onToggleDark,monitorControls=true}:{monitorControls?:boolean,theme:Theme,title:string,subtitle:string,search:string,onSearch:(v:string)=>void,showSearch:boolean,paused:boolean,onPause:()=>void,onExport:()=>void,onConnect:()=>void,onToggleSidebar:()=>void,dark:boolean,onToggleDark:()=>void}){
  return <header className="toolbar">
    {theme!=='adwaita'&&<TrafficLights/>}
    <div className="toolbar-group capsule">
      <button type="button" className="tool-button" aria-label="Toggle sidebar" onClick={onToggleSidebar}><PanelLeft size={17}/></button>
    </div>
    <div className="toolbar-title">
      <h1>{title}</h1>
      <p>{subtitle}</p>
    </div>
    <div className="toolbar-spacer"/>
    {showSearch&&<label className="search-field capsule">
      <Search size={15}/>
      <input aria-label="Search" placeholder="Search" value={search} onChange={e=>onSearch(e.target.value)}/>
    </label>}
    <div className="toolbar-group capsule">
      {monitorControls&&<><button type="button" className="tool-button" aria-label={paused?'Resume updates':'Pause updates'} aria-pressed={paused} onClick={onPause}>{paused?<Play size={16}/>:<Pause size={16}/>}</button>
      <button type="button" className="tool-button" aria-label="Export snapshot" onClick={onExport}><Download size={16}/></button></>}
      <button type="button" className="tool-button" aria-label="Toggle color theme" onClick={onToggleDark}>{dark?<Sun size={16}/>:<Moon size={16}/>}</button>
    </div>
    {monitorControls&&<button type="button" className="button primary" onClick={onConnect}><Plug size={15}/><span>Connect</span></button>}
    {theme==='adwaita'&&<GnomeControls/>}
  </header>;
}
