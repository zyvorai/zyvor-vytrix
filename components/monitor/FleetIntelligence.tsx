'use client';
// SPDX-License-Identifier: BUSL-1.1
import {BrainCircuit,Flame,Microchip,Zap} from 'lucide-react';
import type {ClusterSnapshot} from '@/lib/cluster';
import {fleetIntelligence} from '@/lib/intelligence';
import {bytes} from '@/lib/telemetry';
import {Card} from './primitives';

export function FleetIntelligence({cluster}:{cluster:ClusterSnapshot}){
  const x=fleetIntelligence(cluster.nodes);
  return <div className="cluster-summary">
    <Card><strong><Microchip size={18}/> {x.gpuDevices}</strong><span>GPU devices · {x.gpuAverage===null?'no utilization counter':`${x.gpuAverage.toFixed(1)}% avg`}</span></Card>
    <Card><strong><BrainCircuit size={18}/> {x.aiWorkloads}</strong><span>AI workloads · {bytes(x.aiMemory)} memory</span></Card>
    <Card><strong><Zap size={18}/> {x.powerWatts===null?'—':`${x.powerWatts.toFixed(1)} W`}</strong><span>Fleet power · {x.metalNodes} Metal · {x.aneNodes} ANE</span></Card>
    <Card><strong><Flame size={18}/> {x.maxTemperature===null?'—':`${x.maxTemperature.toFixed(1)} °C`}</strong><span>Peak readable temperature</span></Card>
  </div>;
}
