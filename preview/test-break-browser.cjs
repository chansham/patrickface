const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const output = path.resolve(__dirname, '../output/playwright/20261008-break');
fs.mkdirSync(output, { recursive: true });
const saved = page => page.evaluate(() => JSON.parse(localStorage.getItem('patrick.experience.v1')));
async function ready(page) {
  await page.goto(address);
  await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready');
  await page.locator('[data-experience-tab=timer]').click();
}
(async () => {
  const browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_EXECUTABLE_PATH ? { executablePath: process.env.CHROMIUM_EXECUTABLE_PATH } : {}) });
  const report = { cases: [], nativeDeviceTested: false };
  try {
    for (const paused of [false, true]) {
      const context = await browser.newContext({ viewport: paused ? { width: 390, height: 844 } : { width: 1440, height: 1100 } });
      const page = await context.newPage(), errors = [];
      page.on('pageerror', error => errors.push(error.message));
      try {
        await page.clock.install({ time: new Date('2026-10-08T06:00:00Z') });
        await page.clock.pauseAt(new Date('2026-10-08T06:01:00Z'));
        await ready(page);
        await page.locator('#activity-minutes').fill('5');
        await page.locator('#start-activity').click();
        await page.clock.runFor(20000);
        if (paused) await page.locator('#pause-activity').click();
        const original = (await saved(page)).activity;
        await page.locator('#break-minutes').selectOption('1');
        await page.locator('#begin-break').click();
        let state = await saved(page);
        const held = state.breakSession.savedActivity;
        assert.equal(held.id, original.id);
        assert.ok(held.remainingMs >= 279000 && held.remainingMs <= 280000);
        assert.equal(state.activity.kind, 'breathing');
        assert.equal(await page.locator('#start-activity').isDisabled(), true);
        await page.locator('#exercise-timer').dispatchEvent('click');
        assert.deepEqual((await saved(page)).breakSession.savedActivity, held);
        if (paused) await page.locator('#stop-timer').click();
        else await page.clock.runFor(65000);
        await ready(page);
        state = await saved(page);
        assert.deepEqual(state.breakSession.savedActivity, held);
        if (paused) assert.equal(state.activity, null);
        else assert.notEqual(state.activity.completedAt, null);
        assert.equal(await page.locator('#saved-activity').isVisible(), true);
        await page.screenshot({ path: path.join(output, paused ? 'paused-mobile.png' : 'completed-desktop.png'), fullPage: true });
        await page.locator('#return-activity').click();
        state = await saved(page);
        assert.equal(state.activity.id, original.id);
        assert.equal(state.activity.paused, paused);
        assert.equal(state.activity.remainingMs, held.remainingMs);
        assert.equal(state.breakSession, null);
        const journalCount = state.journal.length, end = state.activity.endsAt;
        await page.locator('#return-activity').dispatchEvent('click');
        state = await saved(page);
        assert.equal(state.journal.length, journalCount);
        assert.equal(state.activity.endsAt, end);
        if (paused) assert.equal(state.activity.endsAt, null);
        else assert.ok(end > await page.evaluate(() => Date.now()));
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
        assert.deepEqual(errors, []);
        report.cases.push({ name: paused ? 'paused-cancel-reload-return-mobile' : 'running-expire-reload-explicit-return', passed: true });
      } finally { await context.close(); }
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    try {
      await ready(page); await page.locator('#start-activity').click(); await page.locator('#begin-break').click();
      const before = await saved(page);
      page.once('dialog', dialog => dialog.dismiss());
      await page.locator('#discard-saved-activity').click();
      assert.deepEqual((await saved(page)).breakSession, before.breakSession);
      page.once('dialog', dialog => dialog.accept());
      await page.locator('#discard-saved-activity').click();
      const after = await saved(page);
      assert.equal(after.breakSession, null); assert.equal(after.activity.id, before.activity.id);
      assert.equal(after.care.bond, before.care.bond);
      report.cases.push({ name: 'discard-requires-explicit-confirmation-and-keeps-break', passed: true });
    } finally { await context.close(); }
  } catch (error) { report.error = error.stack; process.exitCode = 1; }
  finally { await browser.close(); fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report, null, 2)); }
})();
