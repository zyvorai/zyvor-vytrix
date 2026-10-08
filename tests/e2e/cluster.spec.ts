// SPDX-License-Identifier: Apache-2.0
import {test,expect} from '@playwright/test';
import {demoCluster} from '../../lib/cluster';

async function openCluster(page:import('@playwright/test').Page){
  await page.goto('/');
  await page.locator('html[data-transparency]').waitFor({state:'attached'});
  if(await page.getByRole('button',{name:'Toggle sidebar'}).isVisible()&&!(await page.locator('.nav-item:visible').filter({hasText:'Mac cluster'}).count()))await page.getByRole('button',{name:'Toggle sidebar'}).click();
  await page.locator('.nav-item:visible').filter({hasText:'Mac cluster'}).first().click();
}

test('cluster demo shows machines and inspects one, with no controls @mobile',async({page})=>{
  await openCluster(page);
  await expect(page.getByRole('heading',{name:'Connect your cluster'})).toBeVisible();
  await expect(page.getByText('2 / 3',{exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:/^(Start|Stop|Restart)$/})).toHaveCount(0);
  await page.getByRole('button',{name:'Inspect mac-mini-01',exact:true}).click();
  await expect(page.getByText('mac-mini-01 · Machine details')).toBeVisible();
  await page.getByRole('button',{name:'Close details'}).click();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

test('cluster login, live readings, session kept in memory and sign out',async({page})=>{
  const data=demoCluster();data.actor='Viewer';
  await page.route('http://127.0.0.1:9848/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path==='/v1/login')return route.fulfill({json:{token:'test-session'}});
    if(path==='/v1/logout')return route.fulfill({json:{ok:true}});
    return route.fulfill({json:data});
  });
  await openCluster(page);
  await page.getByLabel('Username',{exact:true}).fill('viewer');
  await page.getByLabel('Password',{exact:true}).fill('secure-cluster-password');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await expect(page.getByText('Viewer · viewer · Tokens stay in tab memory')).toBeVisible();
  await expect(page.getByText('Join another Mac')).toHaveCount(0);
  await page.locator('.nav-item:visible').filter({hasText:'Overview'}).first().click();
  await page.locator('.nav-item:visible').filter({hasText:'Mac cluster'}).first().click();
  await expect(page.getByRole('button',{name:'Sign out'})).toBeVisible();
  expect(await page.evaluate(()=>Object.values(localStorage).some(v=>v.includes('test-session')))).toBe(false);
  await page.getByRole('button',{name:'Sign out'}).click();
  await expect(page.getByRole('heading',{name:'Connect your cluster'})).toBeVisible();
});

test('only an administrator is offered pairing',async({page})=>{
  const data=demoCluster();data.role='admin';data.actor='Admin';
  await page.route('http://127.0.0.1:9848/**',route=>route.fulfill({json:data}));
  await openCluster(page);
  await page.getByLabel('Session token (optional)').fill('admin-session');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  await expect(page.getByText('Join another Mac')).toBeVisible();
});
