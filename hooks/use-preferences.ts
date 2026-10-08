'use client';
// SPDX-License-Identifier: Apache-2.0
import {useCallback,useEffect,useState} from 'react';

export type Appearance='auto'|'light'|'dark';
export type ThemeChoice='auto'|'glass'|'macos27'|'adwaita';
export type Theme='glass'|'macos27'|'adwaita';
export const accents=['blue','purple','pink','red','orange','yellow','green','graphite'] as const;
export type Accent=typeof accents[number];

export type Preferences={
  appearance:Appearance;
  theme:ThemeChoice;
  accent:Accent;
  reduceTransparency:boolean;
  alertsEnabled:boolean;
  threshold:number;
};

const KEY='vytrix-preferences';
export const defaultPreferences:Preferences={appearance:'auto',theme:'auto',accent:'blue',reduceTransparency:false,alertsEnabled:true,threshold:80};

function load():Preferences{
  const prefs={...defaultPreferences};
  try{
    const saved=JSON.parse(localStorage.getItem(KEY)||'null') as Partial<Preferences>|null;
    if(saved){
      if(['auto','light','dark'].includes(saved.appearance as string))prefs.appearance=saved.appearance!;
      if(['auto','glass','macos27','adwaita'].includes(saved.theme as string))prefs.theme=saved.theme!;
      if(accents.includes(saved.accent as Accent))prefs.accent=saved.accent!;
      if(typeof saved.reduceTransparency==='boolean')prefs.reduceTransparency=saved.reduceTransparency;
      if(typeof saved.alertsEnabled==='boolean')prefs.alertsEnabled=saved.alertsEnabled;
      if(Number(saved.threshold)>=1&&Number(saved.threshold)<=100)prefs.threshold=Number(saved.threshold);
    }else{
      const legacyTheme=localStorage.getItem('vytrix-theme');
      if(legacyTheme==='dark'||legacyTheme==='light')prefs.appearance=legacyTheme;
      const legacyThreshold=Number(localStorage.getItem('vytrix-threshold'));
      if(legacyThreshold>=1&&legacyThreshold<=100)prefs.threshold=legacyThreshold;
    }
  }catch{}
  return prefs;
}

export function usePreferences(){
  const [prefs,setPrefs]=useState<Preferences>(defaultPreferences);
  const [loaded,setLoaded]=useState(false);
  const [systemDark,setSystemDark]=useState(false);

  useEffect(()=>{
    const media=matchMedia('(prefers-color-scheme: dark)');
    const sync=()=>setSystemDark(media.matches);
    const frame=requestAnimationFrame(()=>{setPrefs(load());setLoaded(true);sync();});
    media.addEventListener('change',sync);
    return()=>{cancelAnimationFrame(frame);media.removeEventListener('change',sync);};
  },[]);

  const dark=prefs.appearance==='dark'||(prefs.appearance==='auto'&&systemDark);

  useEffect(()=>{
    if(!loaded)return;
    const root=document.documentElement;
    root.classList.toggle('dark',dark);
    root.dataset.accent=prefs.accent;
    root.dataset.transparency=prefs.reduceTransparency?'reduced':'full';
    root.style.colorScheme=dark?'dark':'light';
    localStorage.setItem(KEY,JSON.stringify(prefs));
  },[prefs,dark,loaded]);

  const update=useCallback(<K extends keyof Preferences>(key:K,value:Preferences[K])=>setPrefs(p=>({...p,[key]:value})),[]);
  return {prefs,update,dark};
}

export function viewerPlatform():'macos'|'linux'|'other'{
  if(typeof navigator==='undefined')return 'macos';
  const ua=navigator.userAgent;
  if(/Mac|iPhone|iPad/.test(ua))return 'macos';
  if(/Linux|X11|CrOS/.test(ua))return 'linux';
  return 'other';
}
