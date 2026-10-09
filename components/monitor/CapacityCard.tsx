'use client';
// SPDX-License-Identifier: BUSL-1.1
import type {Snapshot} from '@/lib/telemetry';
import {fleetCapacity} from '@/lib/forecast';
import {Card} from './primitives';
export function CapacityCard({history}:{history:Snapshot[]}){const c=fleetCapacity(history);const eta=(v:number|null)=>v===null?'Stable':v<24?`${v.toFixed(1)}h to limit`:`${(v/24).toFixed(1)}d to limit`;return <Card><div className="section-bar"><div><h3>Capacity intelligence</h3><p className="muted">Local trend and anomaly detection; no telemetry leaves Vytrix.</p></div></div><div className="cluster-summary"><div><strong>{eta(c.cpu.etaHours)}</strong><span>CPU · {c.cpu.anomaly?'anomaly':'normal'}</span></div><div><strong>{eta(c.memory.etaHours)}</strong><span>Memory · {c.memory.anomaly?'anomaly':'normal'}</span></div><div><strong>{eta(c.disk.etaHours)}</strong><span>Disk · {c.disk.anomaly?'anomaly':'normal'}</span></div></div></Card>}
