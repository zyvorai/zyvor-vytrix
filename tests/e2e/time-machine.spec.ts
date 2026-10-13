// SPDX-License-Identifier: BUSL-1.1
import {test,expect} from '@playwright/test';
import {demoSnapshot} from '../../lib/telemetry';

test('time machine scrubs stored samples and returns to live',async({page})=>{
  const base=Date.now();
  const sample=(i:number,cpu:number)=>({...demoSnapshot(),cpu,timestamp:new Date(base-(10-i)*2000).toISOString()});
  await page.route('http://127.0.0.1:9847/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path==='/v1/snapshot')return route.fulfill({json:{...demoSnapshot(),cpu:11,timestamp:new Date().toISOString()}});
    if(path==='/v1/history')return route.fulfill({json:{version:1,samples:Array.from({length:10},(_,i)=>sample(i,i===0?77:20))}});
    return route.fulfill({status:404,json:{}});
  });
  await page.goto('/');
  await page.locator('html[data-transparency]').waitFor({state:'attached'});
  await expect(page.getByRole('button',{name:'Time machine'})).toHaveCount(0);   // not for demo data
  await page.locator('.toolbar').getByRole('button',{name:'Connect'}).click();
  await page.getByLabel('Collector endpoint').fill('http://127.0.0.1:9847/v1/snapshot');
  await page.getByLabel('Access token').fill('t'.repeat(32));
  await page.getByRole('button',{name:'Connect',exact:true}).last().click();
  await page.locator('.nav-item:visible').filter({hasText:'CPU'}).first().click();
  await expect(page.locator('.hero-card')).toContainText('11.0');
  await page.getByRole('button',{name:'Time machine'}).click();
  await expect(page.getByText('sample 10 of 10')).toBeVisible();
  const slider=page.getByRole('slider',{name:'Time machine'});
  await slider.fill('0');
  await expect(page.getByText('sample 1 of 10')).toBeVisible();
  await expect(page.locator('.hero-card')).toContainText('77.0');
  await page.getByRole('button',{name:'Back to live'}).click();
  await expect(page.getByText(/sample \d+ of/)).toHaveCount(0);
  await expect(page.locator('.hero-card')).toContainText('11.0');
});
