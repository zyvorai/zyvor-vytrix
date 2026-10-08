// SPDX-License-Identifier: Apache-2.0
import ts from 'typescript';
import {readFile,writeFile,unlink} from 'node:fs/promises';
import assert from 'node:assert/strict';
const compiled=[];
try {
  for(const name of ['telemetry','cluster']){
    const out=new URL(`../lib/.${name}-cluster-test.mjs`,import.meta.url);
    const source=(await readFile(new URL(`../lib/${name}.ts`,import.meta.url),'utf8')).replace("'./telemetry'","'./.telemetry-cluster-test.mjs'");
    await writeFile(out,ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText);
    compiled.push(out);
  }
  const {clusterSchema,clusterOrigin,demoCluster}=await import(compiled[1].href);
  const demo=demoCluster();
  assert(clusterSchema.safeParse(demo).success);
  assert.equal(demo.nodes.length,3);
  assert(!clusterSchema.safeParse({...demo,role:'root'}).success);
  assert(!clusterSchema.safeParse({...demo,role:'operator'}).success,'there is no operator role: the cluster is read-only');
  assert(!clusterSchema.safeParse({...demo,nodes:[{...demo.nodes[0],snapshot:{...demo.nodes[0].snapshot,cpu:900}}]}).success);
  for(const origin of ['http://mac.example','https://user:secret@mac.example','https://mac.example/path','https://mac.example?token=secret','https://mac.example#fragment'])assert.throws(()=>clusterOrigin(origin));
  assert.equal(clusterOrigin('https://mac.example/'),'https://mac.example');
  assert.equal(clusterOrigin('http://127.0.0.1:9848'),'http://127.0.0.1:9848');
  console.log('Cluster schema and URL security tests passed.');
} finally {await Promise.all(compiled.map(p=>unlink(p).catch(()=>{})));}
