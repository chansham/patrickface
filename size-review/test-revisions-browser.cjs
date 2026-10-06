const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/20261006-revisions');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/';
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json')));
const candidates = JSON.parse(fs.readFileSync(path.join(root, 'animation/candidates.json')));
const wanted = process.env.REVIEW_IDS?.split(',').filter(Boolean);
const revisions = candidates.clips.filter(clip => clip.atlas && clip.comparisonClipId && (!wanted || wanted.includes(clip.id)));
const storageKey = 'patrick.size-review.v1';
const mainClip = catalog.clips.find(clip => clip.id === 'focus');
const mainKey = `${mainClip.id}:${mainClip.version}:${mainClip.sha256}:${mainClip.frameRegions.sha256}:${mainClip.scale}`;
const oldNote = { clipID: mainClip.id, verdict: 'revise', text: '既有意見測試留存', artApproval: false };
const seeded = {
  [storageKey]: JSON.stringify({ version: 1, notes: { [mainKey]: oldNote } }),
  'patrick.animation-review.patrick-bedtime-yawn-v1.v2': JSON.stringify({ verdict: 'revise', text: '歷史意見留存' }),
  'patrick.experience.v1': JSON.stringify({ fixture: 'existing daily state must stay unchanged' }),
};
fs.mkdirSync(output, { recursive: true });
const report = { startedAt: new Date().toISOString(), artApproval: false, cases: [] };
(async () => {
  assert.ok(revisions.length, 'No actual comparisonClipId revisions are ready; do not test fake replacements.');
  if (wanted) assert.deepEqual(revisions.map(clip => clip.id).sort(), wanted.sort());
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
  await context.addInitScript(seed => {
    if (!sessionStorage.getItem('revision-test-seeded')) {
      for (const [key, value] of Object.entries(seed)) localStorage.setItem(key, value);
      sessionStorage.setItem('revision-test-seeded', 'yes');
    }
  }, seeded);
  const page = await context.newPage(), errors = [], requests = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(request.url()));
  async function ready() { await page.waitForFunction(() => window.__patrickSizeReview?.status === 'ready'); }
  async function check(name, body) {
    const result = { name, passed: false }; report.cases.push(result);
    try { await body(result); result.passed = true; console.log('PASS ' + name); }
    catch (error) { result.error = error.stack; console.error('FAIL ' + name + ': ' + error.message); await page.screenshot({ path: path.join(output, name + '-failure.png'), fullPage: true }).catch(() => {}); }
  }
  try {
    await check('default-daily-catalog-and-old-opinions-unchanged', async result => {
      await page.goto(address + 'size-review/'); await ready();
      assert.equal(await page.evaluate(() => __patrickSizeReview.candidateMode), false);
      assert.deepEqual(await page.evaluate(() => __patrickSizeReview.candidateClipIDs), []);
      assert.ok(!requests.some(url => url.includes('/animation/candidates.json')));
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
      await page.locator('#note-clip').selectOption('focus');
      assert.equal(await page.locator('#note').inputValue(), oldNote.text);
      result.mainClips = await page.evaluate(() => __patrickSizeReview.clipIDs);
    });
    for (const clip of revisions) await check('actual-old-new-' + clip.id, async result => {
      const previous = catalog.clips.find(value => value.id === clip.comparisonClipId);
      assert.ok(previous, 'Comparison target must be actual main catalog clip');
      await page.goto(address + `size-review/?review=candidates&left=${encodeURIComponent(previous.id)}&right=${encodeURIComponent(clip.id)}`);
      await ready();
      assert.equal(await page.locator('#compare-0').inputValue(), previous.id);
      assert.equal(await page.locator('#compare-1').inputValue(), clip.id);
      assert.equal(await page.evaluate(() => __patrickSizeReview.state.playing), false);
      assert.ok(await page.locator('#revision-banner').isVisible());
      assert.equal(await page.locator('#outfit-grid .card').count(), 11);
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
      await page.locator('#guides').uncheck();
      await page.locator('#compare-grid').screenshot({ path: path.join(output, clip.id + '-old-new-first.png') });
      result.geometry = await page.evaluate(id => {
        const select = document.querySelector('#frame-1');
        return Array.from({ length: Number(select.max) + 1 }, (_, index) => __patrickSizeReview.geometry(id, index, 'classic'));
      }, clip.id);
      assert.equal(result.geometry.length, clip.frameCount);
      assert.equal(new Set(result.geometry.map(value => JSON.stringify(value.rect))).size, 1);
      assert.equal(new Set(result.geometry.map(value => value.pixelScale)).size, 1);
      assert.equal(new Set(result.geometry.map(value => JSON.stringify(value.anchor))).size, 1);
      for (let index = 0; index < clip.frameCount; index++) {
        await page.locator('#frame-1').fill(String(index)); await page.locator('#frame-1').dispatchEvent('input');
        const views = await page.locator('[data-side="1"] canvas').evaluateAll(nodes => nodes.map(node => ({ frame: node.dataset.frame, rect: node.dataset.rect, pixels: node.getContext('2d').getImageData(0, 238, 832, 754).data.some((value, i) => i % 4 !== 3 && value > 35) })));
        assert.ok(views.every(view => view.frame === String(index) && view.pixels));
        assert.equal(views[0].rect, views[1].rect);
      }
      await page.locator('#frame-0').fill(String(previous.frameCount - 1));
      await page.locator('#frame-0').dispatchEvent('input');
      await page.locator('#compare-grid').screenshot({ path: path.join(output, clip.id + '-old-new-last.png') });
      await page.evaluate(() => {
        window.__observedRevision = []; window.__revisionWatching = true;
        function tick() { if (!__revisionWatching) return; const pair = __patrickSizeReview.state.pair.map(value => value.index); if (!__observedRevision.length || pair.join() !== __observedRevision.at(-1).pair.join()) __observedRevision.push({ at: performance.now(), pair }); requestAnimationFrame(tick); }
        requestAnimationFrame(tick);
      });
      await page.locator('#play-pair').click();
      await page.waitForFunction(() => !__patrickSizeReview.state.playing, null, { timeout: 15000 });
      result.normalSpeed = await page.evaluate(() => { __revisionWatching = false; return __observedRevision; });
      // The pre-play sample may contain the manual last frame; begin at the first 0/0 sample.
      const start = result.normalSpeed.findIndex(value => value.pair.every(frame => frame === 0));
      assert.ok(start >= 0);
      const observed = result.normalSpeed.slice(start);
      for (const [side, count] of [[0, previous.frameCount], [1, clip.frameCount]]) assert.deepEqual([...new Set(observed.map(value => value.pair[side]))], Array.from({ length: count }, (_, index) => index));
      await page.waitForTimeout(500);
      assert.deepEqual(await page.evaluate(() => __patrickSizeReview.state.pair.map(value => value.index)), [previous.frameCount - 1, clip.frameCount - 1]);
      assert.equal(await page.evaluate(() => __patrickSizeReview.state.playing), false);
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
      result.sourceSha256 = clip.sha256; result.regionsSha256 = clip.frameRegions.sha256;
    });
    await check('candidate-note-isolated-and-exported-with-old-note', async result => {
      const clip = revisions.at(-1); await page.locator('#note-clip').selectOption(clip.id);
      await page.locator('#note-verdict').selectOption('revise'); await page.locator('#note').fill('候選專項測試，不是使用者批准');
      const saved = await page.evaluate(key => JSON.parse(localStorage.getItem(key)), storageKey);
      assert.deepEqual(saved.notes[mainKey], oldNote);
      const candidateKey = `candidate:${clip.id}:${clip.version}:${clip.sha256}:${clip.frameRegions.sha256}:${clip.scale}`;
      assert.equal(saved.notes[candidateKey].catalog, 'candidates');
      assert.equal(saved.notes[candidateKey].artApproval, false);
      for (const [key, value] of Object.entries(seeded).filter(([key]) => key !== storageKey)) assert.equal(await page.evaluate(key => localStorage.getItem(key), key), value);
      const download = page.waitForEvent('download'); await page.locator('#export').click();
      const file = await download; await file.saveAs(path.join(output, 'isolated-test-opinions.json'));
      const exported = JSON.parse(fs.readFileSync(path.join(output, 'isolated-test-opinions.json')));
      assert.ok(exported.notes.some(note => note.text === oldNote.text));
      assert.ok(exported.notes.some(note => note.clipID === clip.id && note.catalog === 'candidates'));
      await page.reload(); await ready(); await page.locator('#note-clip').selectOption(clip.id);
      assert.equal(await page.locator('#note').inputValue(), '候選專項測試，不是使用者批准');
      result.candidateKey = candidateKey;
    });
    assert.deepEqual(errors, []);
  } finally {
    report.errors = errors; report.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); await browser.close();
  }
  if (report.cases.some(result => !result.passed)) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
