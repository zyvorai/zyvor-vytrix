// SPDX-License-Identifier: BUSL-1.1
import {z} from 'zod';
import {agentHealthSchema,demoSnapshot,inventorySchema,snapshotSchema} from './telemetry';
const id=z.string().min(1).max(128);
export const sessionSchema=z.object({token:z.string().min(1).max(256)});
export const pairingSchema=z.object({code:z.string().min(1).max(128),expires:z.number().finite()});
export const auditSchema=z.object({events:z.array(z.object({id:z.number(),at:z.number(),actor:z.string(),event:z.string()})).max(200)});
export const role=z.enum(['viewer','auditor','editor','admin']);
export const entitlementSchema=z.object({valid:z.boolean().optional(),plan:z.string().max(64).optional(),maxNodes:z.number().int().positive().optional(),features:z.array(z.string().max(128)).optional(),error:z.string().max(128).optional()}).passthrough();
export const clusterSchema=z.object({version:z.literal(1),actor:id,role,nodes:z.array(z.object({id,name:id,seen:z.number().finite().nonnegative(),online:z.boolean(),snapshot:snapshotSchema.nullable(),tags:z.array(z.string().max(64)).max(64).optional(),group:z.string().max(128).nullable().optional(),site:z.string().max(128).nullable().optional(),inventory:inventorySchema.nullable().optional(),agentHealth:agentHealthSchema.nullable().optional()})).max(10000),entitlement:entitlementSchema.optional()});
export type ClusterSnapshot=z.infer<typeof clusterSchema>;
export type ClusterNode=ClusterSnapshot['nodes'][number];
export function clusterOrigin(raw:string){const url=new URL(raw);if(url.username||url.password||url.search||url.hash||!['','/'].includes(url.pathname))throw Error('Enter a coordinator origin without a path or credentials.');if(url.protocol!=='https:'&&!(url.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname)))throw Error('Remote coordinators require HTTPS.');return url.origin;}
export async function clusterRequest(origin:string,path:string,token:string,body?:unknown){const response=await fetch(clusterOrigin(origin)+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)}),redirect:'error',credentials:'omit',cache:'no-store',signal:AbortSignal.timeout(10000)});if(!response.ok){const error=z.object({error:z.string()}).safeParse(await response.json().catch(()=>({})));throw Error(error.success?error.data.error:`Coordinator returned ${response.status}`);}return response.json();}
export function demoCluster():ClusterSnapshot{return{version:1,actor:'Demo',role:'viewer',nodes:Array.from({length:3},(_,i)=>{const snapshot=demoSnapshot(i*7);snapshot.host={...snapshot.host,name:`mac-mini-0${i+1}`,os:'macOS · Demo',cores:12,memoryTotal:32*1024**3};snapshot.cpu=22+i*17;return{id:`demo-${i}`,name:snapshot.host.name,seen:Date.parse(snapshot.timestamp)/1000,online:i!==2,snapshot,tags:i===0?['ai','prod']:['dev'],group:i===0?'inference':'engineering',site:'lab-1'};})};}
