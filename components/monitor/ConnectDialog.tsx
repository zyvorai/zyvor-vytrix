'use client';
// SPDX-License-Identifier: Apache-2.0
import {useState} from 'react';
import {Plug,Upload} from 'lucide-react';
import {Dialog,DialogContent,DialogDescription,DialogTitle} from '@/components/ui/dialog';

export function ConnectDialog({open,onOpenChange,onConnect,onImport,error}:{open:boolean,onOpenChange:(o:boolean)=>void,onConnect:(url:string,token:string)=>Promise<boolean>,onImport:()=>void,error:string}){
  const [url,setUrl]=useState('');
  const [token,setToken]=useState('');
  const [busy,setBusy]=useState(false);
  // Derived during render (not set in an effect): an https dashboard is usually served by its own collector.
  const defaultUrl=open&&typeof location!=='undefined'&&location.protocol==='https:'?`${location.origin}/v1/snapshot`:'';
  const submit=async(e:React.FormEvent)=>{
    e.preventDefault();
    setBusy(true);
    const ok=await onConnect(url||defaultUrl,token);
    setBusy(false);
    if(ok){setToken('');onOpenChange(false);}
  };
  return <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent className="glass-dialog">
      <div className="dialog-icon"><Plug size={22}/></div>
      <DialogTitle className="dialog-title">Connect your system</DialogTitle>
      <DialogDescription className="dialog-text">Run the Vytrix collector on your Mac or Linux host, then enter its HTTPS snapshot endpoint. The token stays in this tab only.</DialogDescription>
      <form className="form" onSubmit={submit}>
        <label className="field"><span>Collector endpoint</span><input required inputMode="url" placeholder="https://monitor.example.com/v1/snapshot" value={url||defaultUrl} onChange={e=>setUrl(e.target.value)}/></label>
        <label className="field"><span>Access token</span><input required type="password" autoComplete="off" value={token} onChange={e=>setToken(e.target.value)}/></label>
        {error&&open&&<p role="alert" className="inline-error">{error}</p>}
        <button className="button primary block" type="submit" disabled={busy}>{busy?'Connecting…':'Connect'}</button>
      </form>
      <div className="divider-label">or work offline</div>
      <button type="button" className="button block" onClick={()=>{onImport();onOpenChange(false);}}><Upload size={15}/>Import collector snapshot</button>
      <p className="fine-print center"><code>python3 agent/vytrix.py --once &gt; snapshot.json</code></p>
    </DialogContent>
  </Dialog>;
}
