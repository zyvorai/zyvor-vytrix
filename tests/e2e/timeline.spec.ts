// SPDX-License-Identifier: BUSL-1.1
import {test,expect} from '@playwright/test';
import {demoSnapshot} from '../../lib/telemetry';

test('timeline lists events and changes from a live collector, and needs a collector otherwise',async({page})=>{
  await page.goto('/');
  await page.locator('html[data-transparency]').waitFor({state:'attached'});
  await page.locator('.nav-item:visible').filter({hasText:'Timeline'}).first().click();
  await expect(page.getByRole('heading',{name:'Timeline needs a collector'})).toBeVisible();

  const now=new Date().toISOString();
  await page.route('http://127.0.0.1:9847/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path==='/v1/snapshot')return route.fulfill({json:{...demoSnapshot(),timestamp:now}});
    if(path==='/v1/timeline')return route.fulfill({json:{version:1,window:{from:0,to:1,samples:120,baselineSamples:120},threshold:85,fingerprint:'0a1b2c3d4e5f',
      events:[{time:now,kind:'alert',subject:'cpu',detail:'fired',severity:'critical',text:'CPU pressure: 97.0%'}],eventCount:1,
      whyChanged:{newSincePrevious:['alert|cpu|fired|critical'],goneSincePrevious:[],previousFingerprint:'ffffffffffff'},notes:['Alert events replay the stored history.']}});
    if(path==='/v1/changes')return route.fulfill({json:{version:1,window:{from:0,to:1,samples:120},
      changes:{appsStarted:['Xcode'],appsStopped:[],portsOpened:[{port:5173,app:'node'}],portsClosed:[],containersAppeared:[],containersGone:[],containersChanged:[],transient:{apps:[],ports:[],containers:[]}},notes:[]}});
    return route.fulfill({status:404,json:{}});
  });
  await page.locator('.toolbar').getByRole('button',{name:'Connect'}).click();
  await page.getByLabel('Collector endpoint').fill('http://127.0.0.1:9847/v1/snapshot');
  await page.getByLabel('Access token').fill('t'.repeat(32));
  await page.getByRole('button',{name:'Connect',exact:true}).last().click();
  await page.locator('.nav-item:visible').filter({hasText:'Timeline'}).first().click();
  await expect(page.getByText('CPU pressure: 97.0%')).toBeVisible();
  await expect(page.getByText('0a1b2c3d4e5f')).toBeVisible();
  await expect(page.getByText('alert cpu fired (critical)')).toBeVisible();
  await expect(page.getByText('Xcode',{exact:true})).toBeVisible();
  await expect(page.getByText('5173 · node')).toBeVisible();
});
