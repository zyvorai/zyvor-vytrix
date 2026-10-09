// SPDX-License-Identifier: BUSL-1.1
import {type Snapshot} from '@/lib/telemetry';

export type Alert={id:string,severity:'warning'|'critical',title:string,text:string};

export function computeAlerts(s:Snapshot,threshold:number):Alert[]{
  const severity=(value:number)=>value>=Math.min(100,threshold+10)?'critical' as const:'warning' as const;
  const alerts:Alert[]=[];
  const memory=s.memoryUsed/s.host.memoryTotal*100;
  const disk=s.diskUsed/s.diskTotal*100;
  if(s.cpu>=threshold)alerts.push({id:'cpu',severity:severity(s.cpu),title:'CPU pressure',text:`Host CPU is ${s.cpu.toFixed(1)}%, above your ${threshold}% threshold.`});
  if(memory>=threshold)alerts.push({id:'memory',severity:severity(memory),title:'Memory pressure',text:`Memory is ${memory.toFixed(0)}% used, above your ${threshold}% threshold.`});
  if(disk>=threshold)alerts.push({id:'disk',severity:severity(disk),title:'Disk nearly full',text:`The root volume is ${disk.toFixed(0)}% full.`});
  for(const c of s.containers??[]){
    if(c.state==='running'&&c.memoryLimit&&c.memory/c.memoryLimit*100>=threshold){
      const pct=c.memory/c.memoryLimit*100;
      alerts.push({id:`container-${c.runtime}-${c.id}`,severity:severity(pct),title:`${c.name} near memory limit`,text:`${c.runtime} container is using ${pct.toFixed(0)}% of its memory limit.`});
    }
  }
  return alerts;
}
