const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/?v=20261013-aftercare1';
const output = path.resolve(__dirname, '../output/playwright/20261013-aftercare-live');
fs.mkdirSync(output, { recursive: true });
const report = { startedAt: new Date().toISOString(), url: address, nativeDeviceTested: false, artApproved: false, cases: [] };
const stored = page => page.evaluate(() => JSON.parse(localStorage.getItem('patrick.experience.v1')));
const snapshot = page => page.evaluate(() => window.__patrickPreviewShell.report);
const effects = page => page.evaluate(() => ({audio:window.__audioPlays.length,haptics:window.__haptics.length}));
async function ready(page) {
  await page.goto(address, {waitUntil:'domcontentloaded'});
  await page.waitForFunction(() => ['ready','error'].includes(window.__patrickPreviewShell?.report.status));
  assert.equal((await snapshot(page)).status,'ready');
  await page.locator('[data-experience-tab=timer]').click();
}
async function start(page, kind = 'exercise') {
  await page.locator('#activity-kind').selectOption(kind);
  // The actual app countdown and completion path run; only the HTML minimum is
  // adjusted to express its existing 10-second engine minimum exactly.
  await page.locator('#activity-minutes').evaluate(input => { input.min = String(1 / 6); });
  await page.locator('#activity-minutes').fill(String(1 / 6));
  await page.locator('#start-activity').click();
  assert.equal((await stored(page)).activity.kind,kind);
}
async function complete(page, kind = 'exercise') {
  await start(page,kind); await page.clock.runFor(11000);
  assert.notEqual((await stored(page)).activity.completedAt,null);
}
async function hidden(page, value) {
  await page.evaluate(value => {
    window.__hidden = value;
    Object.defineProperty(document,'hidden',{configurable:true,get:()=>window.__hidden});
    document.dispatchEvent(new Event('visibilitychange'));
  },value);
}
async function noOffer(page) {
  assert.equal(await page.locator('#aftercare-offer').isVisible(),false);
  assert.notEqual((await snapshot(page)).aftercare.phase,'offered');
}
(async () => {
  const browser = await chromium.launch({headless:true,...(process.env.CHROMIUM_EXECUTABLE_PATH ? {executablePath:process.env.CHROMIUM_EXECUTABLE_PATH}:{})});
  async function test(name, options, run) {
    if (process.env.QA_CASE_FILTER && !new RegExp(process.env.QA_CASE_FILTER).test(name)) return;
    const context = await browser.newContext({viewport:{width:1440,height:1100},timezoneId:'Asia/Hong_Kong',...options});
    const page = await context.newPage(), errors = [], item = {name,passed:false};
    page.on('pageerror',error => errors.push(error.message));
    try {
      await page.addInitScript(() => {
        window.__audioPlays = []; window.__haptics = [];
        HTMLMediaElement.prototype.play = function () { window.__audioPlays.push(this.src); return Promise.resolve(); };
        Object.defineProperty(navigator,'vibrate',{configurable:true,value:value=>{window.__haptics.push(value);return true;}});
      });
      await page.clock.install({time:new Date('2026-10-13T06:01:00Z')});
      await page.clock.pauseAt(new Date('2026-10-13T06:02:00Z'));
      await ready(page); await run(page,item);
      assert.deepEqual(errors,[]); item.passed = true; console.log(`PASS ${name}`);
    } catch (error) {
      item.error = error.stack; item.pageErrors = errors;
      await page.screenshot({path:path.join(output,`${name}-failure.png`),fullPage:true,timeout:3000}).catch(()=>{});
      console.error(`FAIL ${name}: ${error.message}`);
    } finally { report.cases.push(item); await context.close(); }
  }
  try {
    await test('observed-exercise-one-offer-dismiss-reload',{},async(page,item)=>{
      await noOffer(page);
      await page.locator('[data-experience-tab=outfits]').click();
      const outfit = page.locator('[data-outfit]:not([data-outfit="auto"])').first();
      const outfitID = await outfit.getAttribute('data-outfit'); await outfit.click();
      await page.locator('[data-experience-tab=timer]').click();
      await page.locator('.experience-settings summary').click();
      await page.locator('#sound-enabled').check(); await page.locator('#haptics-enabled').check();
      await start(page);
      const before = await stored(page), beforeEffects = await effects(page);
      await page.clock.runFor(11000);
      const after = await stored(page), current = await snapshot(page), afterEffects = await effects(page);
      assert.equal(current.aftercare.phase,'offered'); assert.equal(current.aftercare.mode,'live');
      assert.deepEqual(current.aftercare.availableVariants,['rest']);
      assert.equal(await page.locator('#aftercare-offer').isVisible(),true);
      assert.equal(after.activity.id,before.activity.id);
      assert.equal(after.journal.filter(entry=>entry.type==='complete').length,1);
      assert.equal(after.care.bond,before.care.bond); assert.equal(after.outfitId,outfitID);
      assert.equal(after.settings.sound,true);
      assert.equal(afterEffects.audio-beforeEffects.audio,1,'only the existing completion sound');
      assert.equal(afterEffects.haptics-beforeEffects.haptics,1,'only the existing completion haptic');
      assert.equal(await page.locator('#aftercare-offer a').getAttribute('href'),'../ecosystem/aftercare.html');
      await page.locator('#aftercare-offer').scrollIntoViewIfNeeded();
      await page.screenshot({path:path.join(output,'desktop-offer.png'),fullPage:true});
      await page.locator('#aftercare-dismiss').click(); await noOffer(page);
      assert.deepEqual(await stored(page),after,'dismiss changes no saved companion state');
      assert.deepEqual(await effects(page),afterEffects,'dismiss adds no feedback');
      await ready(page); await noOffer(page);
      assert.equal((await stored(page)).journal.filter(entry=>entry.type==='complete').length,1);
      assert.equal(await page.evaluate(()=>Object.keys(localStorage).some(key=>/aftercare/i.test(key))),false);
      item.outfitPreserved = outfitID;
    });
    await test('explicit-rest-once-mobile',{viewport:{width:390,height:844}},async(page)=>{
      await complete(page,'strength');
      const original = await stored(page);
      await page.locator('#aftercare-offer').scrollIntoViewIfNeeded();
      await page.screenshot({path:path.join(output,'mobile-offer.png'),fullPage:true});
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
      await page.locator('#aftercare-rest').click();
      const after = await stored(page);
      assert.equal(after.activity.kind,'breathing'); assert.equal(after.activity.durationMs,60000);
      assert.notEqual(after.activity.id,original.activity.id); assert.equal(after.activity.completedAt,null);
      assert.equal(after.journal.filter(entry=>entry.type==='timer').length,2);
      assert.equal(after.journal.filter(entry=>entry.type==='complete').length,1);
      assert.equal(after.care.bond,original.care.bond); assert.equal(after.outfitId,original.outfitId);
      assert.equal(after.settings.sound,original.settings.sound);
      await page.locator('#aftercare-rest').dispatchEvent('click');
      assert.deepEqual(await stored(page),after,'a repeated stale button event cannot restart rest');
      await noOffer(page); assert.deepEqual((await snapshot(page)).aftercare.dailyCapabilities,['rest']);
    });
    await test('focus-and-breathing-do-not-offer',{},async(page)=>{
      await complete(page,'focus'); await noOffer(page);
      await complete(page,'breathing'); await noOffer(page);
      assert.equal((await stored(page)).journal.filter(entry=>entry.type==='complete').length,2);
    });
    await test('cancelled-and-paused-exercise-do-not-offer',{},async(page)=>{
      await start(page,'running'); await page.clock.runFor(3000); await page.locator('#stop-timer').click();
      await page.clock.runFor(11000); await noOffer(page);
      assert.equal((await stored(page)).journal.filter(entry=>entry.type==='complete').length,0);
      await start(page,'walking'); await page.locator('#pause-activity').click();
      await page.clock.runFor(11000); await noOffer(page); assert.equal((await stored(page)).activity.paused,true);
    });
    await test('saved-exercise-break-completion-does-not-offer',{},async(page)=>{
      await start(page); await page.clock.runFor(3000);
      await page.locator('#break-minutes').selectOption('1'); await page.locator('#begin-break').click();
      const saved = (await stored(page)).breakSession.savedActivity;
      await page.clock.runFor(61000); await noOffer(page);
      assert.deepEqual((await stored(page)).breakSession.savedActivity,saved);
      assert.equal((await stored(page)).activity.kind,'breathing');
    });
    await test('low-power-completion-does-not-catch-up',{},async(page)=>{
      await start(page); await page.locator('.settings summary').click(); await page.locator('#low-power').check();
      await page.clock.runFor(11000); await noOffer(page);
      await page.locator('#low-power').uncheck(); await page.clock.runFor(1000); await noOffer(page);
    });
    await test('quiet-interrupts-visible-offer',{},async(page)=>{
      await complete(page); assert.equal((await snapshot(page)).aftercare.phase,'offered');
      await page.locator('.settings summary').click(); await page.locator('#wrist-down').check();
      await noOffer(page); await page.locator('#wrist-down').uncheck(); await page.clock.runFor(1000); await noOffer(page);
    });
    await test('background-completion-does-not-catch-up',{},async(page)=>{
      await start(page); await hidden(page,true); await page.clock.runFor(11000);
      await hidden(page,false); await page.clock.runFor(1000); await noOffer(page);
      assert.equal((await stored(page)).journal.filter(entry=>entry.type==='complete').length,1);
    });
    await test('first-open-overdue-completion-does-not-offer',{},async(page)=>{
      await start(page); await page.goto('about:blank'); await page.clock.runFor(11000);
      await ready(page); await noOffer(page);
      assert.equal((await snapshot(page)).aftercare.reason,'notObserved');
      assert.equal((await stored(page)).journal.filter(entry=>entry.type==='complete').length,1);
    });
    await test('offer-expires-and-new-timer-interrupts',{},async(page)=>{
      await complete(page); await page.clock.runFor(61000); await noOffer(page);
      assert.equal((await snapshot(page)).aftercare.reason,'offerExpired');
      await complete(page,'running'); assert.equal((await snapshot(page)).aftercare.phase,'offered');
      await start(page,'focus'); await noOffer(page); assert.equal((await stored(page)).activity.kind,'focus');
    });
    await test('reduced-motion-completion-does-not-offer',{reducedMotion:'reduce'},async(page)=>{
      await complete(page); await noOffer(page);
    });
    await test('entering-art-review-dismisses-live-offer',{},async(page)=>{
      await complete(page); await page.locator('#toggle-review').click(); await noOffer(page);
      assert.equal((await snapshot(page)).aftercare.phase,'dismissed');
    });
  } finally {
    await browser.close(); report.finishedAt = new Date().toISOString();
    report.passed = report.cases.every(item=>item.passed);
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2)); if (!report.passed) process.exitCode = 1;
  }
})();
