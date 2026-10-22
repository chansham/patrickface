const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..'), output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/experience');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const themes = JSON.parse(fs.readFileSync(path.join(root, 'experience/themes.json'), 'utf8'));
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json'), 'utf8'));
const chargingSelection = themes.chargingSelection;
const alternateHidden = new Set(chargingSelection && chargingSelection.alternateVariantsEnabled === false ? (chargingSelection.alternateOutfitIDs || []) : []);
const outfits = themes.outfits.filter(outfit => !alternateHidden.has(outfit.id) && catalog.clips.some(clip => clip.id === outfit.clipId && clip.atlas));
const report = { startedAt: new Date().toISOString(), url: address, artApproved: false, hapticHardwareVerified: false, cases: [] };
fs.mkdirSync(output, { recursive: true });
async function ready(page) {
  await page.goto(address, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => ['ready', 'error'].includes(window.__patrickPreviewShell?.report.status));
  const state = await page.evaluate(() => window.__patrickPreviewShell.report); assert.equal(state.status, 'ready', state.lastError);
  return state;
}
const snapshot = page => page.evaluate(() => window.__patrickPreviewShell.report);
const stored = page => page.evaluate(() => JSON.parse(localStorage.getItem('patrick.experience.v1')));
(async () => {
  const launch = { headless: true }; if (process.env.CHROMIUM_EXECUTABLE_PATH) launch.executablePath = process.env.CHROMIUM_EXECUTABLE_PATH;
  const browser = await chromium.launch(launch);
  async function test(name, options, run) {
    if (process.env.QA_CASE_FILTER && !new RegExp(process.env.QA_CASE_FILTER).test(name)) return;
    const item = { name, passed: false }, context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, timezoneId: 'Asia/Hong_Kong', acceptDownloads: true, ...options });
    const page = await context.newPage(), errors = []; page.on('pageerror', error => errors.push(error.message));
    try {
      await page.addInitScript(() => {
        window.__audioPlays = []; window.__haptics = [];
        const play = HTMLMediaElement.prototype.play;
        HTMLMediaElement.prototype.play = function (...args) { window.__audioPlays.push(this.src); return play.apply(this, args); };
        Object.defineProperty(navigator, 'vibrate', { configurable: true, value: value => { window.__haptics.push(value); return true; } });
      });
      await page.clock.install({ time: new Date('2026-09-27T06:00:00Z') }); await page.clock.pauseAt(new Date('2026-09-27T06:01:00Z'));
      await run(page, item); assert.deepEqual(errors, []); item.passed = true; console.log(`PASS ${name}`);
    } catch (error) { item.error = error.stack; item.pageErrors = errors; console.error(`FAIL ${name}: ${error.message}`); await page.screenshot({ path: path.join(output, `${name}-failure.png`), fullPage: true, timeout: 3000 }).catch(() => {}); }
    finally { report.cases.push(item); await context.close(); }
  }
  try {
    await test('outfits-real-care-mood-journal-and-reload', {}, async (page, item) => {
      const legacy = JSON.stringify({ version: 2, sha256: 'old-source-hash', frames: { 2: 'revise' }, note: 'Never erase this old review.' });
      await page.addInitScript(value => { if (!localStorage.getItem('patrick.animation-review.patrick-bedtime-yawn-v1.v2')) localStorage.setItem('patrick.animation-review.patrick-bedtime-yawn-v1.v2', value); }, legacy);
      await ready(page); assert.equal(await page.locator('#experience-panel').isVisible(), true); assert.equal(await page.locator('.editing').isVisible(), false);
      assert.equal(await page.locator('[data-outfit]').count(), outfits.length + 1); assert.deepEqual(await page.evaluate(() => window.__audioPlays), []);
      assert.equal(await page.locator('[data-outfit="space-charging"]').count(), 0);
      assert.equal(await page.locator('[data-outfit="moon-robe"]').count(), 0);
      await page.locator('[data-outfit="auto"]').click();
      await page.locator('#scene').selectOption('charging');
      assert.equal(await page.locator('#face').getAttribute('data-clip'), 'charging-classic');
      await page.locator('#scene').selectOption('auto');
      await page.locator('[data-experience-tab=outfits]').click();
      for (const outfit of outfits) {
        await page.locator(`[data-outfit="${outfit.id}"]`).click(); assert.equal((await snapshot(page)).outfitPreference, outfit.id); assert.equal(await page.locator('#face').getAttribute('data-clip'), outfit.clipId);
      }
      const explicit = outfits.find(outfit => !outfit.actions?.feed) || outfits[0];
      await page.locator(`[data-outfit="${explicit.id}"]`).click(); await page.locator('[data-experience-tab=care]').click();
      const before = (await snapshot(page)).care;
      await page.locator('#feed').click(); assert.equal((await snapshot(page)).care.totalFeeds, before.totalFeeds + 1); assert.ok((await snapshot(page)).care.satiety > before.satiety);
      if (!explicit.actions?.feed) assert.equal(await page.locator('#face').getAttribute('data-clip'), explicit.clipId, 'missing same-costume feed must not swap outfit');
      await page.locator('#feed').click(); assert.equal((await snapshot(page)).care.totalFeeds, before.totalFeeds + 1);
      await page.clock.runFor(3100); await page.locator('#feed').click(); assert.equal((await snapshot(page)).care.totalFeeds, before.totalFeeds + 2);
      await page.locator('#pet').click(); assert.ok((await snapshot(page)).care.bond >= before.bond + 5);
      await page.locator('#mood').selectOption('grumpy'); assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('patrick.pet.v1')).mood), 'grumpy');
      await page.locator('#scene').selectOption('charging'); assert.equal((await snapshot(page)).outfitPreference, explicit.id);
      await page.locator('[data-experience-tab=journal]').click(); assert.ok(await page.locator('#local-journal li').count() >= outfits.length + 4);
      const downloadPending = page.waitForEvent('download'); await page.locator('#export-journal').click(); const download = await downloadPending; const exportPath = path.join(output, 'little-days.json'); await download.saveAs(exportPath);
      const exported = JSON.parse(fs.readFileSync(exportPath, 'utf8')); assert.equal(exported.journal.filter(entry => entry.type === 'feed').length, 2);
      await ready(page); assert.equal((await snapshot(page)).outfitPreference, explicit.id); assert.equal((await snapshot(page)).care.totalFeeds, before.totalFeeds + 2);
      assert.equal(await page.evaluate(() => localStorage.getItem('patrick.animation-review.patrick-bedtime-yawn-v1.v2')), legacy);
      item.outfitIds = outfits.map(outfit => outfit.id); item.journal = exportPath; await page.screenshot({ path: path.join(output, 'main-care-desktop.png'), fullPage: true });
    });
    await test('exercise-labels-pause-and-reload', {}, async (page, item) => {
      await ready(page);
      item.kinds = [];
      for (const kind of ['walking', 'running', 'strength']) {
        await page.locator('[data-experience-tab=timer]').click();
        await page.locator('#activity-kind').selectOption(kind);
        await page.locator('#activity-minutes').fill('1');
        await page.locator('#start-activity').click();
        assert.equal((await stored(page)).activity.kind, kind);
        assert.equal(await page.locator('#scene').inputValue(), 'exercise');
        assert.equal(await page.locator('#face').getAttribute('data-clip'), 'exercise', 'current shared artwork is used honestly');
        await page.clock.runFor(4500);
        await page.locator('#pause-activity').click();
        const left = (await stored(page)).activity.remainingMs;
        await page.clock.runFor(20000);
        await ready(page);
        await page.locator('[data-experience-tab=timer]').click();
        assert.equal((await stored(page)).activity.kind, kind);
        assert.equal((await stored(page)).activity.remainingMs, left);
        assert.equal((await stored(page)).activity.paused, true);
        assert.match(await page.locator('#timer-status').textContent(), /暫停/);
        await page.locator('#resume-activity').click();
        assert.equal((await stored(page)).activity.paused, false);
        await page.locator('#stop-timer').click();
        assert.equal((await stored(page)).activity, null);
        item.kinds.push(kind);
      }
    });
    await test('timer-pause-resume-reload-completion-and-cancel', {}, async (page, item) => {
      await ready(page); await page.locator('[data-experience-tab=timer]').click(); await page.locator('#activity-kind').selectOption('exercise'); await page.locator('#activity-minutes').fill('0.2'); await page.locator('#start-activity').click();
      await page.clock.runFor(5000); await page.locator('#pause-activity').click(); const left = (await stored(page)).activity.remainingMs; assert.ok(left >= 6500 && left <= 7500);
      await page.clock.runFor(30000); assert.equal((await stored(page)).activity.remainingMs, left);
      await ready(page); await page.locator('[data-experience-tab=timer]').click(); assert.equal((await stored(page)).activity.paused, true); assert.match(await page.locator('#timer-status').textContent(), /暫停/);
      await page.locator('#resume-activity').click();
      await page.evaluate(() => { window.__hidden = true; Object.defineProperty(document, 'hidden', { configurable: true, get: () => window.__hidden }); document.dispatchEvent(new Event('visibilitychange')); });
      await page.clock.runFor(15000); assert.equal((await stored(page)).journal.filter(entry => entry.type === 'complete').length, 1); assert.deepEqual(await page.evaluate(() => window.__audioPlays), []);
      await page.evaluate(() => { window.__hidden = false; document.dispatchEvent(new Event('visibilitychange')); }); await page.clock.runFor(2000); assert.equal((await snapshot(page)).playing, false);
      await ready(page); assert.equal((await stored(page)).journal.filter(entry => entry.type === 'complete').length, 1);
      await page.locator('[data-experience-tab=timer]').click(); await page.locator('#focus-timer').click(); await page.locator('#stop-timer').click();
      assert.equal((await stored(page)).activity, null); assert.equal((await stored(page)).journal.filter(entry => entry.type === 'complete').length, 1);
      await page.locator('#breath-timer').click(); await page.clock.runFor(4500); assert.match(await page.locator('#breath-phase').textContent(), /吐氣/);
      await page.emulateMedia({ reducedMotion: 'reduce' }); await page.clock.runFor(1000); assert.match(await page.locator('#breath-phase').textContent(), /安靜/);
      item.remainingAtPauseMs = left; item.completionRewardCount = 1; await page.screenshot({ path: path.join(output, 'paused-breathing-timer.png'), fullPage: true });
    });
    await test('real-wav-gating-quiet-effects-and-current-time-arms', {}, async (page, item) => {
      await ready(page); await page.waitForFunction(() => window.__patrickPreviewShell.report.clockArtLoaded === true);
      assert.deepEqual(await page.evaluate(() => window.__audioPlays), []); await page.locator('#feed').click(); assert.deepEqual(await page.evaluate(() => window.__audioPlays), []);
      await page.locator('.experience-settings summary').click(); await page.locator('#sound-enabled').check();
      const wavResponse = page.waitForResponse(response => response.url().endsWith('.wav') && response.status() === 200);
      await page.locator('#test-sound').click(); const wav = await wavResponse; const data = await wav.body(); assert.equal(data.subarray(0, 4).toString(), 'RIFF'); assert.ok(data.length > 44);
      item.realAudioURL = wav.url(); item.audioBytes = data.length; item.hapticAPICalls = await page.evaluate(() => window.__haptics.length);
      await page.locator('#time-format').selectOption('12'); assert.equal(await page.locator('#digital-time').textContent(), '02:01'); assert.equal(await page.locator('#digital-time').getAttribute('data-period'), 'PM');
      await page.locator('#date-enabled').uncheck(); assert.equal(await page.locator('#watch-date').isVisible(), false);
      await page.locator('#clock-mode').selectOption('arms'); await page.clock.runFor(100);
      if ((await snapshot(page)).playing) {
        const actingId = (await snapshot(page)).currentClip, acting = catalog.clips.find(clip => clip.id === actingId);
        assert.equal((await snapshot(page)).armClockActive, false, 'a feeding performance finishes before hands return');
        await page.clock.runFor(acting.durationsMs.reduce((a, b) => a + b, 0) + 500);
      }
      assert.equal((await snapshot(page)).armClockActive, true); assert.match(await page.locator('#clock-mode-status').textContent(), /經典造型/);
      const date = new Date(await page.locator('#digital-time').getAttribute('datetime')); const minutes = date.getUTCMinutes() + date.getUTCSeconds() / 60;
      const expectedHour = (((date.getUTCHours() + 8) % 12) + minutes / 60) * Math.PI / 6; assert.ok(Math.abs((await snapshot(page)).armAngles.hour - expectedHour) < .001);
      await page.locator('.enlarged .screen').screenshot({ path: path.join(output, 'real-time-arm-clock.png') });
      await page.locator('#play').click(); assert.equal((await snapshot(page)).playing, true); await page.clock.runFor(100); assert.equal((await snapshot(page)).armClockActive, false);
      const currentId = (await snapshot(page)).currentClip, current = catalog.clips.find(clip => clip.id === currentId);
      await page.clock.runFor(current.durationsMs.reduce((a, b) => a + b, 0) + 500); assert.equal((await snapshot(page)).armClockActive, true);
      await page.locator('#scene').selectOption('charging'); await page.clock.runFor(100); assert.equal((await snapshot(page)).ambienceActive, true);
      await page.emulateMedia({ reducedMotion: 'reduce' }); await page.clock.runFor(500); assert.equal((await snapshot(page)).ambienceActive, false);
      const audioBefore = await page.evaluate(() => window.__audioPlays.length); await page.locator('#pet').click(); assert.equal(await page.evaluate(() => window.__audioPlays.length), audioBefore);
      await page.screenshot({ path: path.join(output, 'clock-and-preferences-desktop.png'), fullPage: true });
    });
    await test('calendar-sleep-preferences-and-quiet-no-catchup', {}, async (page, item) => {
      await ready(page); await page.locator('.experience-settings summary').click();
      await page.locator('#sleep-start').fill('13:00'); await page.locator('#sleep-end').fill('15:00');
      await page.clock.runFor(1000); assert.equal((await snapshot(page)).outfit, 'star-pajamas');
      assert.equal((await stored(page)).settings.sleepStartMinutes, 780);
      await page.locator('#sleep-end').fill('13:00'); await page.clock.runFor(1000); assert.equal((await snapshot(page)).outfit, 'classic');
      await page.locator('#birthday').fill('09-27'); await page.locator('#birthday').blur(); await page.clock.runFor(1000);
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 1);
      await ready(page); await page.clock.runFor(1000); assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 1);
      await page.evaluate(() => { window.__hidden = true; Object.defineProperty(document, 'hidden', { configurable: true, get: () => window.__hidden }); document.dispatchEvent(new Event('visibilitychange')); });
      await page.clock.setSystemTime(new Date('2027-09-27T06:02:00Z')); await page.clock.runFor(1000);
      assert.ok((await stored(page)).easterEggs['birthday-2027-09-27']);
      await page.evaluate(() => { window.__hidden = false; document.dispatchEvent(new Event('visibilitychange')); }); await page.clock.runFor(1000);
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 1, 'quiet birthday is recorded seen without a catchup performance');
      await page.clock.setSystemTime(new Date('2027-10-31T06:02:00Z')); await page.clock.runFor(1000);
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 2);
      await ready(page); await page.locator('.experience-settings summary').click(); await page.locator('#holidays-enabled').uncheck();
      await page.clock.setSystemTime(new Date('2027-12-25T06:02:00Z')); await page.clock.runFor(1000);
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 2);
      await page.locator('#holidays-enabled').check(); await page.clock.runFor(1000);
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 3);
      await ready(page); await page.locator('.settings summary').click();
      const before = await page.locator('#digital-time').getAttribute('datetime');
      await page.locator('#scene-date').fill('2027-02-06'); await page.locator('#scene-date').blur();
      assert.match(await page.locator('#date-status').textContent(), /農曆新年/);
      assert.equal(await page.locator('#digital-time').getAttribute('datetime'), before, 'calendar preview cannot change actual clock time');
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'celebrate').length, 4);
      await page.locator('#little-surprise').click(); await page.locator('#little-surprise').click();
      assert.equal((await stored(page)).journal.filter(entry => entry.type === 'surprise').length, 1);
      const pets = (await snapshot(page)).care.totalPets; await page.locator('#face').press('Enter');
      assert.equal((await snapshot(page)).care.totalPets, pets + 1, 'keyboard and pointer activate the same care action');
      await page.locator('#play').click(); assert.equal((await snapshot(page)).reviewing, false, 'normal play does not silently freeze everyday idle');
      item.calendarEvents = 4; item.quietBirthdaySkipped = true; item.sleepScheduleDisabledByEqualTimes = true;
      await page.screenshot({ path: path.join(output, 'sleep-calendar-preferences.png'), fullPage: true });
    });
    await test('clock-geometry-at-representative-times', {}, async (page, item) => {
      await ready(page); await page.waitForFunction(() => window.__patrickPreviewShell.report.clockArtLoaded === true);
      await page.locator('#toggle-review').click(); await page.locator('.experience-settings summary').click();
      await page.locator('#clock-mode').selectOption('arms');
      item.manifest = JSON.parse(fs.readFileSync(path.join(root, 'experience/clock/manifest.json'), 'utf8'));
      item.observations = [];
      for (const [label, iso] of [['1401', '2026-09-27T06:01:00Z'], ['0000', '2026-09-26T16:00:00Z'], ['0630', '2026-09-26T22:30:00Z'], ['1010', '2026-09-27T02:10:00Z']]) {
        await page.clock.setSystemTime(new Date(iso)); await page.clock.runFor(1000);
        const state = await snapshot(page); assert.equal(state.armClockActive, true);
        const date = new Date(await page.locator('#digital-time').getAttribute('datetime'));
        const m = date.getUTCMinutes() + date.getUTCSeconds() / 60;
        assert.ok(Math.abs(state.armAngles.minute - m * Math.PI / 30) < .002);
        const file = `clock-${label}.png`; await page.locator('.enlarged .screen').screenshot({ path: path.join(output, file) });
        item.observations.push({ time: label, datetime: date.toISOString(), angles: state.armAngles, screenshot: file });
      }
      item.artQualityApproved = false;
    });
    await test('clock-art-failure-keeps-main-care-and-digital-clock', {}, async page => {
      await page.route('**/experience/clock/layers-v1.png*', route => route.fulfill({ status: 404, body: 'not found' }));
      await ready(page); await page.waitForFunction(() => window.__patrickPreviewShell.report.clockArtLoaded === false);
      await page.locator('.experience-settings summary').click(); await page.locator('#clock-mode').selectOption('arms'); assert.match(await page.locator('#clock-mode-status').textContent(), /未載入/);
      const before = (await snapshot(page)).care.totalFeeds; await page.locator('#feed').click(); assert.equal((await snapshot(page)).care.totalFeeds, before + 1);
      const time = await page.locator('#digital-time').getAttribute('datetime'); await page.clock.runFor(61000); assert.ok(Date.parse(await page.locator('#digital-time').getAttribute('datetime')) > Date.parse(time));
    });
    await test('mobile-outfits-and-main-review-toggle', { viewport: { width: 390, height: 900 } }, async page => {
      await ready(page); assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.locator('[data-experience-tab=outfits]').click(); await page.screenshot({ path: path.join(output, 'main-outfits-mobile-390.png'), fullPage: true });
      await page.locator('.experience-settings summary').click();
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.screenshot({ path: path.join(output, 'main-preferences-mobile-390.png'), fullPage: true });
      await page.locator('#toggle-review').click(); assert.equal(await page.locator('.editing').isVisible(), true);
      await page.locator('#frames .frame').nth(0).click(); await page.locator('#review-note').fill('QA：主頁逐格意見仍能保存'); assert.match(await page.locator('#save-status').textContent(), /已儲存/);
    });
  } finally { await browser.close(); report.finishedAt = new Date().toISOString(); report.passed = report.cases.every(item => item.passed); fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); }
  if (!report.passed) process.exitCode = 1;
})();
