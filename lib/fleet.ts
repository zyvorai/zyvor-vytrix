// SPDX-License-Identifier: BUSL-1.1
import {z} from 'zod';
import {clusterRequest} from './cluster';
export const alertRuleSchema=z.object({id:z.number().int().optional(),name:z.string().min(1).max(128),metric:z.enum(['cpu','memoryPercent','diskPercent','download','upload','temperatureCelsius','powerWatts','gpuPercent','agentFailures']),op:z.enum(['>','>=','<','<=']),threshold:z.number().finite(),severity:z.enum(['info','warning','critical']),enabled:z.boolean().optional(),group:z.string().max(128).nullable().optional()});
export const alertEventSchema=z.object({id:z.number().int(),rule_id:z.number().int().nullable().optional(),node_id:z.string().nullable().optional(),opened:z.number().nullable().optional(),last_seen:z.number().nullable().optional(),closed:z.number().nullable().optional(),status:z.string().nullable().optional(),value:z.number().nullable().optional(),message:z.string().nullable().optional()});
export async function getRules(origin:string,token:string){const r=await clusterRequest(origin,'/v1/fleet/rules',token);return z.object({rules:z.array(alertRuleSchema.passthrough())}).parse(r).rules;}
export async function saveRule(origin:string,token:string,rule:z.infer<typeof alertRuleSchema>){return clusterRequest(origin,'/v1/fleet/rules',token,rule);}
export async function getAlerts(origin:string,token:string){const r=await clusterRequest(origin,'/v1/fleet/alerts',token);return z.object({events:z.array(alertEventSchema)}).parse(r).events;}
export async function setNodeMeta(origin:string,token:string,node:string,tags:string[],group:string|null,site:string|null){return clusterRequest(origin,'/v1/fleet/meta',token,{node,tags,group,site});}
export async function addWebhook(origin:string,token:string,name:string,url:string,secret:string){return clusterRequest(origin,'/v1/fleet/webhooks',token,{name,url,secret});}
