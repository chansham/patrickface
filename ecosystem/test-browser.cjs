const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const output = process.env.QA_OUTPUT || path.resolve(__dirname, '../output/playwright/20261007-ecosystem');
const url = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/ecosystem/';
(async () => {
  fs.mkdirSync(output, {recursive:true}); const report = {cases:[], errors:[], simulationOnly:true};
  const browser = await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
  try {
    const context = await browser.newContext({viewport:{width:1440,height:1100},reducedMotion:'no-preference'}), page = await context.newPage();
    page.on('pageerror',error => report.errors.push(error.message));
    await page.addInitScript(() => { localStorage.setItem('patrick.experience.v1','keep-existing-experience'); });
    await page.goto(url); await page.waitForFunction(() => window.__patrickEcosystem?.status === 'ready');
    assert.equal(await page.locator('.card').count(),26);
    await page.locator('#send').click(); await page.waitForFunction(() => !__patrickEcosystem.playing);
    const live = await page.evaluate(() => ({...__patrickEcosystem}));
    assert.equal(live.playedEvents,1); assert.deepEqual(live.frames,Array.from({length:live.frameCount},(_,i)=>i));
    await page.locator('#repeat').click(); assert.equal(await page.evaluate(()=>__patrickEcosystem.outcome),'duplicate');
    assert.equal(await page.evaluate(()=>__patrickEcosystem.playedEvents),1);
    report.cases.push({name:'real-once-playback-and-dedup',passed:true,frames:live.frames});
    await page.locator('#delivery').selectOption('late'); await page.locator('#send').click(); assert.equal(await page.evaluate(()=>__patrickEcosystem.reason),'stale');
    await page.locator('#delivery').selectOption('future'); await page.locator('#send').click(); assert.equal(await page.evaluate(()=>__patrickEcosystem.outcome),'invalid');
    await page.locator('#delivery').selectOption('fresh'); await page.locator('#quiet').check(); await page.locator('#send').click(); assert.equal(await page.evaluate(()=>__patrickEcosystem.reason),'quiet');
    await page.locator('#quiet').uncheck(); await page.locator('#repeat').click(); assert.equal(await page.evaluate(()=>__patrickEcosystem.outcome),'duplicate');
    assert.equal(await page.evaluate(()=>__patrickEcosystem.playedEvents),1);
    report.cases.push({name:'stale-future-quiet-no-replay',passed:true});
    await page.getByRole('button',{name:'健康',exact:true}).click(); assert.equal(await page.locator('.card').count(),9);
    await page.getByRole('button',{name:'全部',exact:true}).click();
    assert.equal(await page.evaluate(()=>localStorage.getItem('patrick.experience.v1')),'keep-existing-experience');
    assert.equal(await page.evaluate(()=>localStorage.length),1);
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.screenshot({path:path.join(output,'desktop.png'),fullPage:true});
    await page.setViewportSize({width:390,height:844}); assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.screenshot({path:path.join(output,'mobile.png'),fullPage:true});
    report.cases.push({name:'filter-responsive-state-isolation',passed:true});
    const reduced = await browser.newContext({reducedMotion:'reduce'}), quietPage = await reduced.newPage();
    await quietPage.goto(url); await quietPage.waitForFunction(()=>window.__patrickEcosystem?.status==='ready'); await quietPage.locator('#send').click();
    assert.equal(await quietPage.evaluate(()=>__patrickEcosystem.playedEvents),0); await reduced.close();
    report.cases.push({name:'system-reduced-motion-respected',passed:true});
    const broken = await context.newPage(); await broken.route('**/animation/wake-v1/regions-v1.json',route=>route.fulfill({status:404,body:'not found'}));
    await broken.goto(url); await broken.waitForFunction(()=>window.__patrickEcosystem?.status==='error'); assert.equal(await broken.locator('#send').isDisabled(),true);
    report.cases.push({name:'missing-source-fails-closed',passed:true});
    assert.deepEqual(report.errors,[]); report.passed=true;
  } catch(error) {report.failure=error.stack; throw error;}
  finally { fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)); await browser.close(); }
  console.log(`PASS ${report.cases.length} ecosystem browser cases`);
})();
