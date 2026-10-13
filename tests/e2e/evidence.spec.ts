// SPDX-License-Identifier: BUSL-1.1
import {test,expect} from '@playwright/test';
import {demoSnapshot} from '../../lib/telemetry';

const iso=(offsetSeconds:number)=>new Date(Date.now()+offsetSeconds*1000).toISOString();

async function connect(page:import('@playwright/test').Page){
  await page.route('http://127.0.0.1:9847/**',async route=>{
    const url=new URL(route.request().url());
    if(url.pathname==='/v1/snapshot')return route.fulfill({json:{...demoSnapshot(),timestamp:new Date().toISOString()}});
    if(url.pathname==='/v1/anomalies')return route.fulfill({json:{
      version:1,warmupSamples:150,threshold:4,metrics:['cpu','memory','disk','network'],rate:{},
      samples:[{timestamp:iso(-60),cpu:{score:6.2,anomalous:true},memory:null,disk:null,network:null}],
      windows:[{metric:'cpu',start:iso(-90),end:iso(-60),peak:6.2,samples:12}]}});
    if(url.pathname==='/v1/evidence')return route.fulfill({json:{
      version:1,metric:'cpu',window:{from:0,to:1,samples:30,baselineSamples:30},
      host:{cpu:{mean:61.5,peak:88.2}},baselineHost:{cpu:{mean:20.1,peak:31}},
      apps:[{name:'python',mean:44.2,peak:70.1,present:30,samples:30,baselineMean:3.1,delta:41.1}],
      containers:[],anomalies:{windows:[],peaks:{},scoredSamples:30},notes:['Memory is RSS.']}});
    return route.fulfill({status:404,json:{}});
  });
  await page.goto('/');
  await page.locator('html[data-transparency]').waitFor({state:'attached'});
  await page.locator('.toolbar').getByRole('button',{name:'Connect'}).click();
  await page.getByLabel('Collector endpoint').fill('http://127.0.0.1:9847/v1/snapshot');
  await page.getByLabel('Access token').fill('t'.repeat(32));
  await page.getByRole('button',{name:'Connect',exact:true}).last().click();
}

test('live collector: anomaly band, evidence sheet, token stays in memory',async({page})=>{
  await connect(page);
  await page.locator('.nav-item:visible').filter({hasText:'CPU'}).first().click();
  await expect(page.locator('.anomaly-band').first()).toBeAttached();
  await page.getByRole('button',{name:'What was busy in this range?'}).click();
  const sheet=page.getByRole('dialog');
  await expect(sheet.getByText('What was busy: CPU')).toBeVisible();
  await expect(sheet.getByRole('cell',{name:'python'})).toBeVisible();
  await expect(sheet.getByText('+41.1%')).toBeVisible();
  await expect(sheet.getByText('Memory is RSS.',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>Object.values(localStorage).some(v=>v.includes('ttttt')))).toBe(false);
});

test('demo data has no evidence controls',async({page})=>{
  await page.goto('/');
  await page.locator('.nav-item:visible').filter({hasText:'CPU'}).first().click();
  await expect(page.getByRole('button',{name:'What was busy in this range?'})).toHaveCount(0);
  await expect(page.locator('.anomaly-band')).toHaveCount(0);
});
