// SPDX-License-Identifier: BUSL-1.1
import {z} from 'zod';
import type {Snapshot} from './telemetry';

const metric=z.number().finite().nonnegative();
const percent=z.number().finite().min(0).max(100);
export const aiProcessSchema=z.object({engine:z.string().min(1).max(128),kind:z.string().min(1).max(64),confidence:z.number().int().min(0).max(100),markers:z.array(z.string().max(64)).max(16)});
export const aiWorkloadSchema=z.object({engine:z.string().min(1).max(128),kind:z.string().min(1).max(64),processes:z.number().int().nonnegative(),cpu:metric,memory:metric,diskReadRate:metric,diskWriteRate:metric,confidence:z.number().int().min(0).max(100)});
export const gpuSchema=z.object({name:z.string().max(256),backend:z.string().max(64).optional(),utilization:percent.optional()});
export const acceleratorSchema=z.object({type:z.enum(['gpu','npu','other']),name:z.string().max(256),backend:z.string().max(64).nullable().optional(),available:z.boolean()});
export const hardwareSchema=z.object({chip:z.string().max(256).optional(),gpus:z.array(gpuSchema).max(32).optional(),accelerators:z.array(acceleratorSchema).max(32).optional(),metal:z.object({available:z.boolean()}).optional(),ane:z.object({available:z.boolean(),utilization:percent.nullable()}).optional(),temperatureCelsius:z.number().finite().min(-50).max(200).optional(),temperatures:z.array(z.object({name:z.string().max(128),celsius:z.number().finite().min(-50).max(200)})).max(64).optional(),powerWatts:metric.optional(),thermalLimits:z.object({cpuSpeedLimit:percent.optional(),cpuSchedulerLimit:percent.optional()}).optional()});

export type Hardware=z.infer<typeof hardwareSchema>;
export type AIWorkload=z.infer<typeof aiWorkloadSchema>;

export function fleetIntelligence(nodes:Array<{online:boolean,snapshot:Snapshot|null}>){
  const online=nodes.filter(n=>n.online&&n.snapshot);
  const snapshots=online.map(n=>n.snapshot!);
  const gpu=snapshots.flatMap(s=>s.hardware?.gpus??[]).map(g=>g.utilization).filter((x):x is number=>x!==undefined);
  const power=snapshots.map(s=>s.hardware?.powerWatts).filter((x):x is number=>x!==undefined);
  const temps=snapshots.map(s=>s.hardware?.temperatureCelsius).filter((x):x is number=>x!==undefined);
  const ai=snapshots.flatMap(s=>s.aiWorkloads??[]);
  return {
    online:online.length,
    gpuDevices:snapshots.reduce((n,s)=>n+(s.hardware?.gpus?.length??0),0),
    gpuAverage:gpu.length?gpu.reduce((a,b)=>a+b,0)/gpu.length:null,
    gpuPeak:gpu.length?Math.max(...gpu):null,
    powerWatts:power.length?power.reduce((a,b)=>a+b,0):null,
    maxTemperature:temps.length?Math.max(...temps):null,
    aiWorkloads:ai.length,
    aiCpu:ai.reduce((n,w)=>n+w.cpu,0),
    aiMemory:ai.reduce((n,w)=>n+w.memory,0),
    metalNodes:snapshots.filter(s=>s.hardware?.metal?.available).length,
    aneNodes:snapshots.filter(s=>s.hardware?.ane?.available).length,
  };
}
