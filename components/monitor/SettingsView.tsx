'use client';
// SPDX-License-Identifier: Apache-2.0
import {Download,Upload} from 'lucide-react';
import {Switch} from '@/components/ui/switch';
import {accents,type Preferences,type Theme} from '@/hooks/use-preferences';
import {type Source} from '@/hooks/use-telemetry';
import {Card,Segmented} from './primitives';

function Row({title,text,children}:{title:string,text?:string,children:React.ReactNode}){
  return <div className="setting-row"><div><h3>{title}</h3>{text&&<p>{text}</p>}</div><div className="setting-control">{children}</div></div>;
}

export function SettingsView({prefs,update,resolvedTheme,source,onImport,onExport,onUseDemo}:{prefs:Preferences,update:<K extends keyof Preferences>(k:K,v:Preferences[K])=>void,resolvedTheme:Theme,source:Source,onImport:()=>void,onExport:()=>void,onUseDemo:()=>void}){
  return <div className="settings-grid">
    <Card className="settings-card">
      <h2>Appearance</h2>
      <Row title="Appearance" text="Auto follows your system light/dark setting.">
        <Segmented label="Appearance" value={prefs.appearance} onChange={v=>update('appearance',v)} options={[{value:'auto',label:'Auto'},{value:'light',label:'Light'},{value:'dark',label:'Dark'}]}/>
      </Row>
      <Row title="Window style" text={`Auto picks from the monitored host. Currently ${{glass:'macOS 26 Liquid Glass',macos27:'macOS 27',adwaita:'Linux Adwaita'}[resolvedTheme]}.`}>
        <Segmented label="Window style" value={prefs.theme} onChange={v=>update('theme',v)} options={[{value:'auto',label:'Auto'},{value:'glass',label:'macOS 26'},{value:'macos27',label:'macOS 27'},{value:'adwaita',label:'Linux'}]}/>
      </Row>
      <Row title="Accent color">
        <div className="swatches" role="radiogroup" aria-label="Accent color">{accents.map(a=><button key={a} type="button" role="radio" aria-checked={prefs.accent===a} aria-label={a} className={`swatch ${a}`} onClick={()=>update('accent',a)}/>)}</div>
      </Row>
      <Row title="Reduce transparency" text="Use solid surfaces instead of glass. Also honours the system accessibility setting.">
        <Switch checked={prefs.reduceTransparency} onCheckedChange={v=>update('reduceTransparency',v)} aria-label="Reduce transparency"/>
      </Row>
    </Card>
    <Card className="settings-card">
      <h2>Alerts</h2>
      <Row title="Resource alerts" text="Check CPU, memory, disk and container limits.">
        <Switch checked={prefs.alertsEnabled} onCheckedChange={v=>update('alertsEnabled',v)} aria-label="Enable resource alerts"/>
      </Row>
      <Row title="Threshold" text={`Alert at ${prefs.threshold}% or higher.`}>
        <div className="range"><input type="range" min={10} max={100} step={1} value={prefs.threshold} onChange={e=>update('threshold',Number(e.target.value))} aria-label="Alert threshold percent" style={{'--range-fill':`${(prefs.threshold-10)/90*100}%`} as React.CSSProperties}/><output className="num">{prefs.threshold}%</output></div>
      </Row>
    </Card>
    <Card className="settings-card">
      <h2>Data</h2>
      <Row title="Snapshot" text="Import real collector output, or export the current sample as JSON.">
        <div className="button-row"><button type="button" className="button" onClick={onImport}><Upload size={15}/>Import</button><button type="button" className="button" onClick={onExport}><Download size={15}/>Export</button></div>
      </Row>
      <Row title="Data source" text={source==='demo'?'Simulated data is running.':source==='live'?'Polling your collector every 2 seconds.':'Viewing a single imported snapshot.'}>
        <button type="button" className="button" disabled={source==='demo'} onClick={onUseDemo}>Use demo data</button>
      </Row>
      <p className="fine-print">History shows samples captured while this page is open. The collector keeps up to 30 days in SQLite. GPU, fans, audio and Bluetooth are not collected in this release.</p>
    </Card>
  </div>;
}
