// Uses a disposable browser profile. Never touches the user's saved feedback.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '../..');
const read = p => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8').replace(/^\uFEFF/, ''));
const catalog = read('animation/candidates.json');
const fitness = catalog.clips.filter(c => c.batch === '20261012-fitness');
const fitnessCollection = catalog.clips.filter(c => c.batch === '20261012-fitness' || c.collectionTags?.includes('fitness'));
const newestDay = catalog.clips.map(c => c.batch || '').map(b => b.slice(0, 8)).sort().at(-1);
const newestBatch = catalog.clips.filter(c => c.batch?.startsWith(newestDay)).at(-1).batch;
assert.ok(fitness.length >= 8, 'Wait for the full batch; partial loading is not completion.');
const out = path.join(root, 'output/playwright/fitness-20261012/final-ui');
fs.mkdirSync(out, { recursive: true });
const report = { artApproval: false, cases: [], errors: [], fitnessIDs: fitness.map(c => c.id) };
const sentinels = {
  'patrick.pet.v1': '{"doNotReplace":"existing daily pet"}',
  'patrick.experience.v1': '{"doNotReplace":"existing preferences"}',
  'patrick.size-review.v1': '{"version":1,"notes":{"old":{"text":"existing size opinion"}}}',
  'patrick.frame-review.v1': '{"version":1,"notes":{}}'
};
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
  const page = await context.newPage();
  page.on('pageerror', e => report.errors.push(e.message));
  try {
    await page.goto('http://127.0.0.1:8765/preview/?review=candidates&group=fitness&v=20261012-fitness1');
    await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready', null, { timeout: 120000 });
    await page.evaluate(values => { for (const [k, v] of Object.entries(values)) localStorage.setItem(k, v); }, sentinels);
    assert.deepEqual(await page.evaluate(() => __patrickPreviewShell.report.clipsFailed), []);
    const options = () => page.locator('#clip-select option').evaluateAll(nodes => nodes.map(n => n.value));
    assert.deepEqual(await options(), fitnessCollection.map(c => c.id));
    await page.locator('[data-candidate-filter="new"]').click();
    assert.deepEqual(await options(), catalog.clips.filter(c => c.batch === newestBatch).map(c => c.id), 'Same-day names must not override catalog batch order.');
    await page.locator('[data-candidate-filter="fitness"]').click();
    report.cases.push({ name: 'fitness-and-latest-batch-filters', passed: true });
    for (const clip of fitness) {
      await page.locator('#clip-select').selectOption(clip.id);
      const state = await page.evaluate(() => __patrickPreviewShell.report);
      assert.equal(state.currentClip, clip.id);
      assert.equal(state.rendering[clip.id].sourceImageHash, clip.sha256);
      const link = new URL(await page.locator('#size-review-link').getAttribute('href'));
      assert.equal(link.searchParams.get('right'), clip.id);
      assert.equal(link.searchParams.get('review'), 'candidates');
      for (let i = 0; i < clip.frameCount; i++) {
        if (i) await page.locator('#next-frame').click();
        const frames = await page.locator('#face, #wrist-face').evaluateAll(nodes => nodes.map(c => ({
          frame: Number(c.dataset.frame), clip: c.dataset.clip,
          painted: c.getContext('2d').getImageData(0, 0, c.width, c.height).data.some((v, i) => i % 4 === 3 && v > 0)
        })));
        for (const f of frames) assert.deepEqual(f, { frame: i, clip: clip.id, painted: true });
      }
      const frameBefore = await page.locator('#face').getAttribute('data-frame');
      await page.locator('[data-candidate-filter="fitness"]').click();
      assert.equal(await page.locator('#clip-select').inputValue(), clip.id);
      assert.equal(await page.locator('#face').getAttribute('data-frame'), frameBefore);
      report.cases.push({ name: 'all-visible-source-frames-and-size-link', id: clip.id, frames: clip.frameCount, passed: true });
    }
    const chosen = fitness[0];
    await page.locator('#clip-select').selectOption(chosen.id);
    await page.locator('#next-frame').click();
    await page.locator('#verdict').selectOption('revise');
    await page.locator('#review-note').fill('QA fitness opinion survives filtering and reload.');
    await page.locator('[data-candidate-filter="all"]').click();
    await page.locator('[data-candidate-filter="fitness"]').click();
    assert.equal(await page.locator('#review-note').inputValue(), 'QA fitness opinion survives filtering and reload.');
    await page.reload();
    await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready', null, { timeout: 120000 });
    await page.locator('#clip-select').selectOption(chosen.id);
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#export-review').click();
    const download = await downloadPromise, exportPath = path.join(out, 'sample-candidate-export.json');
    await download.saveAs(exportPath);
    const exported = JSON.parse(fs.readFileSync(exportPath, 'utf8'));
    assert.equal(exported.clips.length, catalog.clips.length, 'Filtering must never omit earlier reviews from export.');
    assert.ok(JSON.stringify(exported.clips.find(c => c.asset === chosen.id)).includes('QA fitness opinion'));
    report.cases.push({ name: 'filter-safe-review-save-reload-export', passed: true });
    await page.locator('#size-review-link').click();
    await page.waitForFunction(() => window.__patrickSizeReview?.status === 'ready', null, { timeout: 120000 });
    assert.equal(await page.evaluate(() => __patrickSizeReview.state.pair[1].id), chosen.id);
    for (const clip of fitness) {
      const e = await page.evaluate(id => __patrickSizeReview.evidence(id), clip.id);
      assert.equal(e.evidenceComplete, true, clip.id);
      assert.equal(e.artApproval, false);
      report.cases.push({ name: 'source-pinned-anatomy-evidence', id: clip.id, passed: true });
    }
    const cycling = fitness.find(c => c.id.includes('cycling'));
    const e = await page.evaluate(id => __patrickSizeReview.evidence(id), cycling.id);
    assert.equal(e.metrics.faceWidth.measured, 0, 'Helmet strap cannot be silently measured as facial skin.');
    await page.locator('#revision-select').selectOption(cycling.id);
    await page.locator('#guides').uncheck();
    await page.locator('#landmarks').check();
    await page.locator('[data-side="1"] .mark-frame').last().click();
    await page.locator('[name="frame-issue"][value="outfit"]').check();
    await page.locator('#frame-note').fill('QA helmet strap remains an unknown face boundary.');
    const noteDownload = page.waitForEvent('download');
    await page.locator('#export').click();
    const noteFile = path.join(out, 'sample-size-export.json');
    await (await noteDownload).saveAs(noteFile);
    const noteData = JSON.parse(fs.readFileSync(noteFile, 'utf8'));
    const note = noteData.frameNotes.find(n => n.clipID === cycling.id);
    assert.equal(note.sourceSha256, cycling.sha256);
    assert.equal(note.artApproval, false);
    assert.ok(noteData.notes.some(n => n.text === 'existing size opinion'));
    report.cases.push({ name: 'unknown-anatomy-and-version-pinned-feedback', passed: true });
    await page.setViewportSize({ width: 390, height: 844 });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await page.locator('#frame-review').screenshot({ path: path.join(out, 'fitness-frame-review-390.png') });
    for (const key of ['patrick.pet.v1', 'patrick.experience.v1']) assert.equal(await page.evaluate(k => localStorage.getItem(k), key), sentinels[key]);
    assert.deepEqual(report.errors, []);
    report.passed = true;
  } catch (e) {
    report.passed = false; report.failure = e.stack; process.exitCode = 1;
  } finally {
    await context.close(); await browser.close();
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ passed: report.passed, cases: report.cases.length, failure: report.failure, errors: report.errors }));
  }
})();
