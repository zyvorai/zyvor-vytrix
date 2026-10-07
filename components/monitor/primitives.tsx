'use client';
// SPDX-License-Identifier: Apache-2.0
import {useEffect,useId,useRef,useState,type ReactNode} from 'react';

export function AnimatedNumber({value,decimals=0}:{value:number,decimals?:number}){
  const [shown,setShown]=useState(value);
  const current=useRef(value);
  useEffect(()=>{
    const from=current.current;
    const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;
    const start=performance.now();
    let frame=0;
    const step=(now:number)=>{
      const k=reduce?1:Math.min(1,(now-start)/650);
      const eased=1-Math.pow(1-k,3);
      const v=from+(value-from)*eased;
      current.current=v;
      setShown(v);
      if(k<1)frame=requestAnimationFrame(step);
    };
    frame=requestAnimationFrame(step);
    return()=>cancelAnimationFrame(frame);
  },[value]);
  return <>{shown.toFixed(decimals)}</>;
}

function smoothPath(points:[number,number][]){
  if(points.length<2)return '';
  let d=`M${points[0][0]},${points[0][1]}`;
  for(let i=0;i<points.length-1;i++){
    const p0=points[i-1]??points[i],p1=points[i],p2=points[i+1],p3=points[i+2]??p2;
    const c1x=p1[0]+(p2[0]-p0[0])/6,c1y=p1[1]+(p2[1]-p0[1])/6;
    const c2x=p2[0]-(p3[0]-p1[0])/6,c2y=p2[1]-(p3[1]-p1[1])/6;
    d+=` C${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
  }
  return d;
}

export function Sparkline({values,color,height=44,max=100}:{values:number[],color:string,height?:number,max?:number}){
  const id=useId().replace(/:/g,'');
  const width=240;
  const data=(values.length>1?values:[values[0]??0,values[0]??0]).slice(-60);
  const top=Math.max(max,...data);
  const points=data.map((v,i)=>[i/(data.length-1)*width,height-3-(Math.max(0,v)/top)*(height-8)] as [number,number]);
  const line=smoothPath(points);
  return <svg className="sparkline" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" aria-hidden="true">
    <defs><linearGradient id={`g${id}`} x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor={color} stopOpacity=".32"/><stop offset="100%" stopColor={color} stopOpacity="0"/></linearGradient></defs>
    <path d={`${line} L${width},${height} L0,${height} Z`} fill={`url(#g${id})`}/>
    <path d={line} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" vectorEffect="non-scaling-stroke"/>
  </svg>;
}

export function Gauge({value,color,size=64,stroke=7,children}:{value:number,color:string,size?:number,stroke?:number,children?:ReactNode}){
  const r=(size-stroke)/2;
  const c=2*Math.PI*r;
  const pct=Math.max(0,Math.min(100,value));
  return <div className="gauge" style={{width:size,height:size}}>
    <svg viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
      <circle cx={size/2} cy={size/2} r={r} fill="none" className="gauge-track" strokeWidth={stroke}/>
      <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c*(1-pct/100)} transform={`rotate(-90 ${size/2} ${size/2})`} className="gauge-value"/>
    </svg>
    <div className="gauge-label">{children}</div>
  </div>;
}

const iconHues=[211,262,330,4,28,45,140,190];
export function AppIcon({name,size=30}:{name:string,size?:number}){
  let h=0;for(const ch of name)h=(h*31+ch.charCodeAt(0))>>>0;
  const hue=iconHues[h%iconHues.length];
  return <span className="app-icon" style={{width:size,height:size,fontSize:size*.46,background:`linear-gradient(160deg,hsl(${hue} 90% 66%),hsl(${(hue+18)%360} 80% 48%))`}} aria-hidden="true">{name.replace(/^[^A-Za-z0-9]+/,'').slice(0,1).toUpperCase()||'?'}</span>;
}

export function Segmented<T extends string>({value,options,onChange,label}:{value:T,options:readonly {value:T,label:ReactNode}[],onChange:(v:T)=>void,label:string}){
  return <div className="segmented" role="radiogroup" aria-label={label}>
    {options.map(o=><button key={o.value} type="button" role="radio" aria-checked={value===o.value} data-active={value===o.value} onClick={()=>onChange(o.value)}>{o.label}</button>)}
  </div>;
}

export function Meter({value,color,label}:{value:number,color?:string,label?:string}){
  return <div className="meter" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value)} aria-label={label}>
    <i style={{width:`${Math.max(0,Math.min(100,value))}%`,background:color}}/>
  </div>;
}

export function Card({className='',children,...rest}:React.HTMLAttributes<HTMLElement>&{children:ReactNode}){
  return <section className={`card ${className}`} {...rest}>{children}</section>;
}

export function EmptyState({icon,title,children}:{icon:ReactNode,title:string,children?:ReactNode}){
  return <div className="empty-state"><div className="empty-icon">{icon}</div><h3>{title}</h3>{children}</div>;
}
