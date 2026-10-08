// SPDX-License-Identifier: Apache-2.0
import ts from 'typescript';
import {readFile,writeFile,unlink} from 'node:fs/promises';
import assert from 'node:assert/strict';
const compiled=[];
async function load(name){
 const out=new URL(`../lib/.${name}-test.mjs`,import.meta.url);
 const source=await readFile(new URL(`../lib/${name}.ts`,import.meta.url),'utf8');
 await writeFile(out,ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText);
 compiled.push(out);
 return import(out.href);
}
try{
 const {demoSnapshot,groupApps,snapshotSchema,runningContainers,formatPort,platformOf,macMajor}=await load('telemetry');
 const {computeAlerts}=await load('alerts');
 const s=demoSnapshot();assert(snapshotSchema.safeParse(s).success);
 const groups=groupApps(s);assert.equal(groups.length,8);
 assert.equal(groups.reduce((n,g)=>n+g.processes.length,0),s.processes.length);
 assert(Math.abs(groups.reduce((n,g)=>n+g.memory,0)-s.processes.reduce((n,p)=>n+p.memory,0))<.01);
 assert.deepEqual(groups.find(g=>g.name==='node').ports,[5173]);
 for(const cpu of [-1,Infinity,NaN,101])assert(!snapshotSchema.safeParse({...s,cpu}).success);
 assert(!snapshotSchema.safeParse({...s,version:2}).success);
 assert(!snapshotSchema.safeParse({...s,timestamp:'broken'}).success);
 assert(!snapshotSchema.safeParse({...s,processes:[{...s.processes[0],ports:[70000]}]}).success);

 // Containers: optional for backward compatibility with older collectors and imports.
 const legacy={...s};delete legacy.containers;delete legacy.runtimes;
 assert(snapshotSchema.safeParse(legacy).success,'snapshots without containers stay valid');
 assert.equal(runningContainers(legacy).length,0);
 assert.equal(s.containers.length,5);
 assert.equal(runningContainers(s).length,4);
 assert.deepEqual([...new Set(s.containers.map(c=>c.runtime))].sort(),['docker','podman']);
 const c=s.containers[0];
 assert(!snapshotSchema.safeParse({...s,containers:[{...c,runtime:'lxc'}]}).success);
 assert(!snapshotSchema.safeParse({...s,containers:[{...c,cpu:-1}]}).success);
 assert(!snapshotSchema.safeParse({...s,containers:[{...c,ports:[{hostPort:1,containerPort:70000,protocol:'tcp'}]}]}).success);
 assert(!snapshotSchema.safeParse({...s,containers:[{...c,ports:[{hostPort:1,containerPort:80,protocol:'icmp'}]}]}).success);
 assert(snapshotSchema.safeParse({...s,containers:[{...c,memoryLimit:null,ports:[{hostPort:null,containerPort:80,protocol:'udp'}]}]}).success);
 assert(!snapshotSchema.safeParse({...s,runtimes:[{name:'docker',available:'yes',error:null}]}).success);
 assert.equal(formatPort({hostPort:8080,containerPort:80,protocol:'tcp'}),'8080→80/tcp');
 assert.equal(formatPort({hostPort:null,containerPort:443,protocol:'tcp'}),'443/tcp');

 assert.equal(platformOf('macOS 26.0'),'macos');
 assert.equal(platformOf('Darwin 25.6.0'),'macos');
 assert.equal(macMajor('macOS 27.2'),27);
 assert.equal(macMajor('macOS 26.7.1'),26);
 assert.equal(macMajor('Linux 6.8.0'),0);
 assert.equal(platformOf('Linux 6.8.0-45-generic'),'linux');
 assert.equal(platformOf('Linux · Ubuntu 24.04'),'linux');
 assert.equal(platformOf('Windows'),'other');

 const calm={...s,cpu:10,memoryUsed:s.host.memoryTotal*.2,diskUsed:s.diskTotal*.2,containers:[]};
 assert.deepEqual(computeAlerts(calm,80),[]);
 const hot={...calm,cpu:95,containers:[{...c,state:'running',memory:950,memoryLimit:1000}]};
 const alerts=computeAlerts(hot,80);
 assert.deepEqual(alerts.map(a=>a.id),['cpu',`container-${c.runtime}-${c.id}`]);
 assert.equal(alerts[0].severity,'critical');
 console.log('Telemetry tests passed: validation, grouping, containers, backward compatibility, platforms and alerts.');
}finally{await Promise.all(compiled.map(u=>unlink(u).catch(()=>{})));}
