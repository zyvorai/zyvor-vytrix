// SPDX-License-Identifier: BUSL-1.1
import {z} from 'zod';
const num=z.number().finite();
const label=z.string().max(256);
export const anomalyMetrics=['cpu','memory','disk','network'] as const;
export type AnomalyMetric=(typeof anomalyMetrics)[number];
export const evidenceMetrics=['cpu','memory','network'] as const;
export type EvidenceMetric=(typeof evidenceMetrics)[number];

const score=z.object({score:num,anomalous:z.boolean()}).nullable();
const windowSchema=z.object({metric:z.enum(anomalyMetrics),start:z.string().datetime(),end:z.string().datetime(),peak:num,samples:z.number().int().nonnegative()});
/** GET /v1/anomalies. A null score is a metric still warming up or not reported: absent, never zero. */
export const anomalySchema=z.object({
  warmupSamples:z.number().int().nonnegative(),
  threshold:num,
  samples:z.array(z.object({timestamp:z.string().datetime(),cpu:score.optional(),memory:score.optional(),disk:score.optional(),network:score.optional()})).max(5000),
  windows:z.array(windowSchema).max(5000),
});
export type AnomalyReport=z.infer<typeof anomalySchema>;

const stat=z.object({mean:num.nullable(),peak:num.nullable()});
/** GET /v1/evidence. */
export const evidenceSchema=z.object({
  metric:z.enum(evidenceMetrics),
  window:z.object({from:num,to:num,samples:z.number().int().nonnegative(),baselineSamples:z.number().int().nonnegative()}),
  host:z.record(label,stat),
  baselineHost:z.record(label,stat).nullable().optional(),
  apps:z.array(z.object({name:label,mean:num,peak:num.nullable().optional(),present:z.number().int().nonnegative(),samples:z.number().int().nonnegative(),baselineMean:num.nullable().optional(),delta:num.nullable().optional()})).max(100),
  containers:z.array(z.object({name:label.nullable().optional(),runtime:label.nullable().optional(),image:z.string().max(512).nullable().optional(),meanCpu:num.nullable().optional(),peakCpu:num.nullable().optional(),peakMemory:num.nullable().optional(),memoryLimit:num.nullable().optional()})).max(100),
  anomalies:z.object({windows:z.array(windowSchema).max(5000),peaks:z.record(label,num.nullable()),scoredSamples:z.number().int().nonnegative()}),
  notes:z.array(z.string().max(512)).max(50),
});
export type EvidenceReport=z.infer<typeof evidenceSchema>;

/** The history endpoints live next to the snapshot endpoint the person connected. */
export function collectorUrl(snapshotEndpoint:string,path:string){
  return new URL(path,snapshotEndpoint).href;
}

export type Band={from:number,to:number};
/** Anomaly windows of one metric as time bands, widened to two seconds so one sample is visible. */
export function anomalyBands(report:AnomalyReport|null,metric:AnomalyMetric):Band[]{
  if(!report)return [];
  return report.windows.filter(w=>w.metric===metric).map(w=>{const from=Date.parse(w.start);const to=Date.parse(w.end);return {from,to:Math.max(to,from+2000)};});
}
/** True once any sample in the report was scored for the metric (false while it warms up). */
export function isScored(report:AnomalyReport|null,metric:AnomalyMetric){
  return !!report?.samples.some(s=>s[metric]!=null);
}

const eventSchema=z.object({time:z.string().datetime(),kind:z.enum(['alert','container','anomaly']),subject:label,detail:label,severity:label,text:z.string().max(512),end:z.string().datetime().optional(),peak:num.optional()});
/** GET /v1/timeline. */
export const timelineSchema=z.object({
  window:z.object({from:num,to:num,samples:z.number().int().nonnegative(),baselineSamples:z.number().int().nonnegative()}),
  threshold:num,
  fingerprint:z.string().regex(/^[0-9a-f]{12}$/),
  events:z.array(eventSchema).max(200),
  eventCount:z.number().int().nonnegative(),
  whyChanged:z.object({newSincePrevious:z.array(z.string().max(600)).max(500),goneSincePrevious:z.array(z.string().max(600)).max(500),previousFingerprint:z.string().regex(/^[0-9a-f]{12}$/)}).nullable(),
  notes:z.array(z.string().max(512)).max(50),
});
export type TimelineReport=z.infer<typeof timelineSchema>;

const portRow=z.object({port:z.number().int(),app:label});
/** GET /v1/changes. `changes` is null with fewer than two samples. */
export const changesSchema=z.object({
  window:z.object({from:num,to:num,samples:z.number().int().nonnegative(),first:z.string().optional(),last:z.string().optional()}),
  changes:z.object({
    appsStarted:z.array(label),appsStopped:z.array(label),portsOpened:z.array(portRow),portsClosed:z.array(portRow),
    containersAppeared:z.array(label),containersGone:z.array(label),
    containersChanged:z.array(z.object({container:label,from:label.nullable(),to:label.nullable()})),
    transient:z.object({apps:z.array(label),ports:z.array(portRow),containers:z.array(label)}),
  }).nullable(),
  notes:z.array(z.string().max(512)).max(50),
});
export type ChangesReport=z.infer<typeof changesSchema>;
