// SPDX-License-Identifier: BUSL-1.1
import ts from 'typescript';import {readFile,writeFile,unlink} from 'node:fs/promises';import assert from 'node:assert/strict';
// lib/evidence.ts imports zod, so transpile next to it where node_modules resolves.
const src=await readFile(new URL('../lib/evidence.ts',import.meta.url),'utf8');
const out=new URL('../lib/.evidence-test.mjs',import.meta.url);
await writeFile(out,ts.transpileModule(src,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText);
try{
  const {anomalySchema,evidenceSchema,anomalyBands,isScored,collectorUrl}=await import(out.href);
  const report=anomalySchema.parse({warmupSamples:150,threshold:4,samples:[{timestamp:'2026-01-01T00:00:00Z',cpu:null,memory:null,disk:null,network:null}],windows:[{metric:'cpu',start:'2026-01-01T00:00:10Z',end:'2026-01-01T00:00:10Z',peak:5,samples:1}]});
  assert.equal(isScored(report,'cpu'),false,'a warming-up metric is not scored');
  const [band]=anomalyBands(report,'cpu');
  assert.equal(band.to-band.from,2000,'a single sample is widened to two seconds');
  assert.deepEqual(anomalyBands(report,'memory'),[]);
  assert.equal(anomalyBands(null,'cpu').length,0);
  assert.equal(collectorUrl('https://host:9847/v1/snapshot','/v1/anomalies?since=1'),'https://host:9847/v1/anomalies?since=1');
  assert.equal(collectorUrl('https://host/vytrix/v1/snapshot','/v1/anomalies?since=1'),'https://host/vytrix/v1/anomalies?since=1','a reverse-proxy sub-path is kept');
  assert.throws(()=>evidenceSchema.parse({metric:'disk'}));
  console.log('evidence tests passed');
}finally{await unlink(out).catch(()=>{});}
