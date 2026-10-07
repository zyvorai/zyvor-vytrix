'use client';
// SPDX-License-Identifier: Apache-2.0
import {type LucideIcon} from 'lucide-react';
import {type ReactNode} from 'react';
import {AnimatedNumber,Gauge,Sparkline} from './primitives';

export type Metric={id:string,label:string,icon:LucideIcon,value:number|null,decimals?:number,unit:string,hint:ReactNode,color:string,values:number[],gauge?:number,sparkMax?:number};

export function MetricTile({metric,onClick}:{metric:Metric,onClick?:()=>void}){
  const Icon=metric.icon;
  return <button type="button" className="card metric-tile" style={{'--tint':metric.color} as React.CSSProperties} onClick={onClick} aria-label={`${metric.label}: ${metric.value===null?'unavailable':metric.value.toFixed(metric.decimals??0)+' '+metric.unit}`}>
    <div className="metric-head">
      <span className="metric-icon"><Icon size={15} strokeWidth={2.2}/></span>
      <span className="metric-label">{metric.label}</span>
    </div>
    <div className="metric-body">
      <div>
        <div className="metric-value">{metric.value===null?'—':<AnimatedNumber value={metric.value} decimals={metric.decimals}/>}<span>{metric.value===null?'':metric.unit}</span></div>
        <div className="metric-hint">{metric.hint}</div>
      </div>
      {metric.gauge!==undefined&&<Gauge value={metric.gauge} color={metric.color} size={52} stroke={6}><span>{Math.round(metric.gauge)}%</span></Gauge>}
    </div>
    <Sparkline values={metric.values} color={metric.color} max={metric.sparkMax??100}/>
  </button>;
}
