// Actual saved candidate art/durations, disposable profile. No artwork approval.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const out = process.env.QA_OUTPUT || path.join(root, 'output/playwright/reviewflow-20261012');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/candidates.json'), 'utf8'));
const selected = catalog.clips.filter(c => c.batch === '20261012-playful' || c.collectionTags?.includes('playful'));
assert.equal(selected.length, 2, 'Use the two actual playful clips for the real-time sequence check.');
const protectedValues = { 'patrick.pet.v1': '{"keep":"pet"}', 'patrick.experience.v1': '{"keep":"experience"}',
  'patrick.animation-player.v1': '{"keep":"settings"}', 'patrick.animation-events.v1': '{"keep":"events"}' };
const report = { artApproval: false, build: '20261012-reviewflow1', realTime: true,
  actualClips: selected.map(c => ({ id: c.id, sha256: c.sha256, durationsMs: c.durationsMs })), cases: [], errors: [] };
fs.mkdirSync(out, { recursive: true });
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
  const page = await context.newPage(); page.setDefaultTimeout(20000);
  page.on('pageerror', e => report.errors.push(e.message));
  async function ready(url) {
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => ['ready', 'error'].includes(window.__patrickPreviewShell?.report.status), null, { timeout: 120000 });
    const state = await page.evaluate(() => __patrickPreviewShell.report);
    assert.equal(state.status, 'ready', state.lastError); assert.equal(state.build, report.build);
    return state;
  }
  async function group() { return page.evaluate(() => __patrickPreviewShell.report.groupPlayback); }
  async function unchangedAfterStop(ms = 650) {
    const before = await page.locator('#face').evaluate(c => [c.dataset.clip, c.dataset.frame]);
    await wait(ms);
    assert.deepEqual(await page.locator('#face').evaluate(c => [c.dataset.clip, c.dataset.frame]), before);
    assert.equal((await group()).active, false);
  }
  async function restart() {
    await page.locator('[data-candidate-filter=playful]').click();
    await page.locator('#play-group').click();
    await page.waitForFunction(() => __patrickPreviewShell.report.playing && __patrickPreviewShell.report.currentFrame >= 1);
  }
  try {
    await page.addInitScript(values => {
      if (new URL(location.href).searchParams.get('review') !== 'candidates') return;
      for (const [k, v] of Object.entries(values)) if (localStorage.getItem(k) === null) localStorage.setItem(k, v);
      window.__reviewWrites = []; const original = Storage.prototype.setItem;
      Storage.prototype.setItem = function(k, v) { window.__reviewWrites.push(k); return original.call(this, k, v); };
      window.__sequenceFrames = []; let last = '';
      function observe() {
        const shell = window.__patrickPreviewShell?.report, a = document.querySelector('#face'), b = document.querySelector('#wrist-face');
        if (shell?.groupPlayback?.active && shell.playing && a && b) {
          const token = a.dataset.clip + ':' + a.dataset.frame;
          if (token !== last) {
            last = token;
            const pixels = a.getContext('2d').getImageData(0, 0, a.width, a.height).data;
            let painted = 0, checksum = 0;
            for (let i = 0; i < pixels.length; i += 4) if (pixels[i + 3] >= 128) { painted++; checksum = (checksum + pixels[i] * 3 + pixels[i + 1] * 5 + pixels[i + 2] * 7 + i) >>> 0; }
            window.__sequenceFrames.push({ clip: a.dataset.clip, frame: Number(a.dataset.frame), wristClip: b.dataset.clip,
              wristFrame: Number(b.dataset.frame), at: performance.now(), painted, checksum });
          }
        }
        requestAnimationFrame(observe);
      }
      requestAnimationFrame(observe);
    }, protectedValues);
    await ready('http://127.0.0.1:8765/preview/?review=candidates&group=playful');
    assert.deepEqual(await page.evaluate(() => __patrickPreviewShell.report.clipsFailed), []);
    assert.deepEqual(await page.locator('#clip-select option').evaluateAll(nodes => nodes.map(n => n.value)), selected.map(c => c.id));
    await page.locator('#clip-select').selectOption(selected[0].id);
    await page.locator('#review-note').fill('第一套意見：連播後仍保留。');
    await page.locator('#verdict').selectOption('revise');
    await page.locator('#clip-select').selectOption(selected[1].id);
    await page.locator('#review-note').fill('第二套意見：不可串到前一套。');
    await page.locator('#speed').selectOption('0.5');
    const clockBefore = await page.locator('#digital-time').getAttribute('datetime');
    await page.locator('#play-group').click();
    assert.equal(await page.locator('#speed').inputValue(), '1'); assert.equal(await page.locator('#speed').isDisabled(), true);
    await page.waitForFunction(() => __patrickPreviewShell.report.groupPlayback?.completed === 2 && !__patrickPreviewShell.report.groupPlayback.active);
    assert.match(await page.locator('#group-play-status').textContent(), /已看 2 組.*完成/);
    const observations = await page.evaluate(() => __sequenceFrames);
    for (const clip of selected) {
      const seen = observations.filter(f => f.clip === clip.id);
      assert.deepEqual(seen.map(f => f.frame), Array.from({ length: clip.frameCount }, (_, i) => i));
      assert.ok(seen.every(f => f.painted > 1000 && f.wristFrame === f.frame && f.wristClip === f.clip));
      assert.ok(new Set(seen.map(f => f.checksum)).size > 4, 'Different real frame pixels must be drawn.');
      const elapsed = seen.at(-1).at - seen[0].at, expected = clip.durationsMs.slice(0, -1).reduce((a, b) => a + b, 0);
      assert.ok(Math.abs(elapsed - expected) < 250, `normal 1x: ${elapsed} vs ${expected}`);
    }
    assert.ok(Date.parse(await page.locator('#digital-time').getAttribute('datetime')) > Date.parse(clockBefore));
    await unchangedAfterStop();
    report.cases.push({ name: 'two-actual-clips-all-frames-normal-1x-once', passed: true, observations });

    for (let i = 0; i < selected.length; i++) {
      await page.locator('#clip-select').selectOption(selected[i].id);
      assert.match(await page.locator('#review-note').inputValue(), i ? /第二套/ : /第一套/);
    }
    await page.locator('#play-group').click();
    await page.waitForFunction(() => __patrickPreviewShell.report.groupPlayback?.completed === 1 && !__patrickPreviewShell.report.playing);
    assert.equal(await page.locator('#pause').isEnabled(), true);
    await page.locator('#pause').click(); await unchangedAfterStop();
    assert.equal(await page.locator('#face').getAttribute('data-clip'), selected[0].id);
    report.cases.push({ name: 'pause-during-inter-clip-gap-cancels-delayed-switch', passed: true });

    for (const [name, action] of [
      ['next-frame', () => page.locator('#next-frame').click()],
      ['previous-frame', () => page.locator('#previous-frame').click()],
      ['thumbnail', () => page.locator('#frames .frame').nth(3).click()],
      ['select-another-clip', () => page.locator('#clip-select').selectOption(selected[1].id)],
      ['filter', () => page.locator('[data-candidate-filter=fitness]').click()],
      ['write-opinion', () => page.locator('#review-note').fill('寫意見時已停下，不暗中換稿。')],
      ['stop-group-button', () => page.locator('#play-group').click()]
    ]) {
      await restart(); await action(); await unchangedAfterStop();
      report.cases.push({ name: `manual-${name}-cancels-queue`, passed: true });
    }
    await restart();
    await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange')); });
    await unchangedAfterStop();
    await page.evaluate(() => { delete document.hidden; document.dispatchEvent(new Event('visibilitychange')); });
    await unchangedAfterStop();
    report.cases.push({ name: 'visibility-handler-cancels-with-no-resume', passed: true, simulatedVisibilityEvent: true });

    await restart(); await page.locator('#play').click(); assert.equal((await group()).active, false);
    await page.waitForFunction(() => !__patrickPreviewShell.report.playing);
    await unchangedAfterStop();
    report.cases.push({ name: 'single-play-interrupts-queue-and-still-plays-once', passed: true });

    await page.setViewportSize({ width: 390, height: 900 });
    await page.locator('#play-group').scrollIntoViewIfNeeded();
    const mobile = await page.locator('#play-group').boundingBox();
    assert.ok(mobile.x >= 0 && mobile.x + mobile.width <= 390 && mobile.height >= 44);
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: path.join(out, 'candidate-mobile-390.png'), fullPage: false });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.waitForFunction(() => document.querySelector('#play-group').disabled);
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await page.waitForFunction(() => !document.querySelector('#play-group').disabled);
    report.cases.push({ name: '390px-controls-and-reduced-motion', passed: true, bounds: mobile });

    const download = page.waitForEvent('download'); await page.locator('#export-review').click();
    const target = path.join(out, 'candidate-review-export.json'); await (await download).saveAs(target);
    const exported = JSON.parse(fs.readFileSync(target, 'utf8'));
    assert.equal(exported.clips.length, catalog.clips.length);
    assert.match(exported.clips.find(c => c.asset === selected[1].id).sections.action.note, /第二套/);
    for (const [k, v] of Object.entries(protectedValues)) assert.equal(await page.evaluate(k => localStorage.getItem(k), k), v);
    assert.ok((await page.evaluate(() => __reviewWrites)).every(k => k.startsWith('patrick.animation-candidate-review.')));
    await page.reload(); await page.waitForFunction(() => __patrickPreviewShell?.report.status === 'ready', null, { timeout: 120000 });
    await page.locator('#clip-select').selectOption(selected[1].id); assert.match(await page.locator('#review-note').inputValue(), /第二套/);
    assert.equal((await group())?.active || false, false, 'Reload must not restore a queue.');
    report.cases.push({ name: 'notes-export-reload-and-main-storage-isolation', passed: true });

    await page.evaluate(() => { for (const k of Object.keys(localStorage)) if (k.startsWith('patrick.')) localStorage.removeItem(k); });
    await ready('http://127.0.0.1:8765/preview/');
    assert.equal(await page.locator('#play-group').isVisible(), false);
    assert.equal(await page.locator('#group-play-status').isVisible(), false);
    assert.equal(await page.locator('#experience-panel').isVisible(), true);
    await page.locator('#play-group').dispatchEvent('click'); assert.equal((await group())?.active || false, false);
    report.cases.push({ name: 'daily-ui-has-no-group-control-or-programmatic-queue', passed: true });
    assert.deepEqual(report.errors, []);
  } catch (error) {
    report.error = error.stack; console.error(error.stack);
    await page.screenshot({ path: path.join(out, 'failure.png'), fullPage: true, timeout: 5000 }).catch(() => {});
    process.exitCode = 1;
  } finally {
    await browser.close(); report.finishedAt = new Date().toISOString(); report.passed = !report.error && report.errors.length === 0;
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ passed: report.passed, cases: report.cases.length, output: out }));
  }
})();
