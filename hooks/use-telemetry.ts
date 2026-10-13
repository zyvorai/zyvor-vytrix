'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useCallback,useEffect,useRef,useState} from 'react';
import {demoSnapshot,snapshotSchema,type Snapshot} from '@/lib/telemetry';
import {collectorUrl} from '@/lib/evidence';

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
  // Time machine: stored samples and the one shown. Live polling keeps recording underneath.
  const [replay,setReplay]=useState<Snapshot[]>([]);
  const [replayIndex,setReplayIndex]=useState<number|null>(null);
  const replaying=useRef(false);

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
        if(running){if(!replaying.current)setSnapshot(next);setHistory(h=>[...h,next].slice(-MAX_HISTORY));setError('');}
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

  /** GET a history endpoint of the connected collector; null for demo data, imports and failures. */
  const collectorGet=useCallback(async(path:string):Promise<unknown>=>{
    if(source!=='live')return null;
    try{
      const res=await fetch(collectorUrl(endpoint,path),{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(8000)});
      return res.ok?await res.json():null;
    }catch{return null;}
  },[source,endpoint,token]);

  const beginReplay=useCallback(async()=>{
    const since=Math.floor(Date.now()/1000)-3600;
    const raw=await collectorGet(`/v1/history?since=${since}&limit=1000`) as {samples?:unknown}|null;
    const parsed=Array.isArray(raw?.samples)?raw.samples.map(x=>snapshotSchema.safeParse(x)).flatMap(r=>r.success?[r.data]:[]):[];
    if(parsed.length<2)return false;
    replaying.current=true;
    setReplay(parsed);setReplayIndex(parsed.length-1);setSnapshot(parsed[parsed.length-1]);
    return true;
  },[collectorGet]);
  const scrub=useCallback((i:number)=>{
    if(replay[i]){setReplayIndex(i);setSnapshot(replay[i]);}
  },[replay]);
  const endReplay=useCallback(()=>{
    replaying.current=false;setReplayIndex(null);
    const last=history[history.length-1]??replay[replay.length-1];
    if(last)setSnapshot(last);
    setReplay([]);
  },[history,replay]);
  // Leaving the live source leaves the replay.
  useEffect(()=>{if(source!=='live'&&replaying.current){replaying.current=false;setReplayIndex(null);setReplay([]);}},[source]);

  return {snapshot,history,source,paused,setPaused,error,setError,connect,importFile,useDemo,collectorGet,replay,replayIndex,beginReplay,scrub,endReplay};
}
