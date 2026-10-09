'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useCallback,useEffect,useRef,useState} from 'react';
import {demoSnapshot,snapshotSchema,type Snapshot} from '@/lib/telemetry';

export type Source='demo'|'live'|'import';
const MAX_HISTORY=1800;
const POLL_MS=2000;
const MAX_IMPORT_BYTES=10*1024**2;

function seedHistory():Snapshot[]{
  return Array.from({length:60},(_,i)=>({...demoSnapshot(i),timestamp:new Date(Date.now()-(59-i)*POLL_MS).toISOString()}));
}

export function isAllowedCollectorUrl(url:URL){
  return url.protocol==='https:'||(url.protocol==='http:'&&['localhost','127.0.0.1'].includes(url.hostname));
}

export function useTelemetry(){
  const [snapshot,setSnapshot]=useState<Snapshot>(()=>demoSnapshot());
  const [history,setHistory]=useState<Snapshot[]>(seedHistory);
  const [source,setSource]=useState<Source>('demo');
  const [paused,setPaused]=useState(false);
  const [error,setError]=useState('');
  const [endpoint,setEndpoint]=useState('');
  // The token lives only in tab memory: never localStorage, never the hosting server.
  const [token,setToken]=useState('');
  const tick=useRef(60);

  useEffect(()=>{
    if(paused||source==='import')return;
    let running=true,busy=false;
    const update=async()=>{
      if(busy)return;
      busy=true;
      try{
        const next=source==='live'
          ?snapshotSchema.parse(await (await fetch(endpoint,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(8000)})).json())
          :demoSnapshot(tick.current++);
        if(running){setSnapshot(next);setHistory(h=>[...h,next].slice(-MAX_HISTORY));setError('');}
      }catch{
        if(running)setError('Collector unavailable. Last successful sample is shown. Check its address, token, HTTPS and allowed origin.');
      }finally{busy=false;}
    };
    const id=setInterval(update,POLL_MS);
    if(source==='live')void update();
    return()=>{running=false;clearInterval(id);};
  },[source,paused,endpoint,token]);

  const connect=useCallback(async(rawUrl:string,rawToken:string)=>{
    try{
      const url=new URL(rawUrl);
      if(!isAllowedCollectorUrl(url))throw Error();
      const res=await fetch(url.href,{headers:{Authorization:`Bearer ${rawToken}`},signal:AbortSignal.timeout(8000)});
      if(!res.ok)throw Error();
      const next=snapshotSchema.parse(await res.json());
      setSnapshot(next);setHistory([next]);setEndpoint(url.href);setToken(rawToken);setSource('live');setPaused(false);setError('');
      return true;
    }catch{
      setError('Could not connect. Use a valid HTTPS snapshot endpoint, token, and an allowed browser origin.');
      return false;
    }
  },[]);

  const importFile=useCallback(async(file:File)=>{
    try{
      if(file.size>MAX_IMPORT_BYTES)throw Error();
      const next=snapshotSchema.parse(JSON.parse(await file.text()));
      setSnapshot(next);setHistory([next]);setSource('import');setToken('');setError('');
    }catch{
      setError('Invalid snapshot. Import a version 1 JSON export from the Vytrix collector (maximum 10 MB).');
    }
  },[]);

  const useDemo=useCallback(()=>{
    setSource('demo');setPaused(false);setHistory(seedHistory());setToken('');setEndpoint('');setError('');
  },[]);

  return {snapshot,history,source,paused,setPaused,error,setError,connect,importFile,useDemo};
}
