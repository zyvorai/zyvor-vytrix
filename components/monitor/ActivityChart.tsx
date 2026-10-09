'use client';
// SPDX-License-Identifier: BUSL-1.1
import {useId} from 'react';
import {Area,AreaChart,CartesianGrid,ResponsiveContainer,Tooltip,XAxis,YAxis} from 'recharts';

export type Series={key:string,label:string,color:string};
type Point={t:number}&Record<string,number>;

const time=(t:number)=>new Date(t).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',second:'2-digit'});

function GlassTooltip({active,payload,label,format,series}:{active?:boolean,payload?:{dataKey?:unknown,value?:unknown}[],label?:unknown,format:(v:number)=>string,series:Series[]}){
  if(!active||!payload?.length)return null;
  return <div className="chart-tooltip">
    <div className="chart-tooltip-time">{time(Number(label))}</div>
    {payload.map(p=>{const s=series.find(x=>x.key===p.dataKey);return s?<div key={s.key} className="chart-tooltip-row"><i style={{background:s.color}}/><span>{s.label}</span><b>{format(Number(p.value))}</b></div>:null;})}
  </div>;
}

export function ActivityChart({data,series,height=240,domain=[0,100],format=v=>`${v.toFixed(1)}%`}:{data:Point[],series:Series[],height?:number,domain?:[number,number|'auto'],format?:(v:number)=>string}){
  const id=useId().replace(/:/g,'');
  const span=data.length>1?data[data.length-1].t-data[0].t:0;
  return <div className="activity-chart" style={{height}}>
    <ResponsiveContainer width="100%" height="100%" minWidth={0} initialDimension={{width:640,height}}>
      <AreaChart data={data} margin={{top:8,right:8,bottom:0,left:-12}}>
        <defs>{series.map(s=><linearGradient key={s.key} id={`${id}-${s.key}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor={s.color} stopOpacity={.35}/><stop offset="95%" stopColor={s.color} stopOpacity={0}/></linearGradient>)}</defs>
        <CartesianGrid vertical={false} strokeDasharray="2 6" stroke="var(--separator)"/>
        <XAxis dataKey="t" type="number" domain={['dataMin','dataMax']} scale="time" tickFormatter={t=>new Date(t).toLocaleTimeString([],span>600000?{hour:'2-digit',minute:'2-digit'}:{minute:'2-digit',second:'2-digit'})} tick={{fill:'var(--text-tertiary)',fontSize:11}} axisLine={false} tickLine={false} minTickGap={48}/>
        <YAxis domain={domain} tick={{fill:'var(--text-tertiary)',fontSize:11}} axisLine={false} tickLine={false} width={48} tickFormatter={v=>format(Number(v)).replace(/\.0(?=\D|$)/,'')}/>
        <Tooltip cursor={{stroke:'var(--text-tertiary)',strokeDasharray:'3 3'}} content={<GlassTooltip format={format} series={series}/>}/>
        {series.map(s=><Area key={s.key} type="monotone" dataKey={s.key} stroke={s.color} strokeWidth={2.2} fill={`url(#${id}-${s.key})`} isAnimationActive={false} dot={false} activeDot={{r:4,strokeWidth:2,stroke:'var(--surface-solid)'}}/>)}
      </AreaChart>
    </ResponsiveContainer>
  </div>;
}

export function ChartLegend({series}:{series:Series[]}){
  return <div className="chart-legend">{series.map(s=><span key={s.key}><i style={{background:s.color}}/>{s.label}</span>)}</div>;
}
