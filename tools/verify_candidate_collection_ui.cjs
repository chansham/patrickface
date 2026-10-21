// Disposable context: this verification never accesses the user's browser profile.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const batch = process.argv[2];
if (!/^\d{8}-[a-z]+$/.test(batch || '')) throw new Error('Pass an existing candidate batch.');
const read = p => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8').replace(/^\uFEFF/, ''));
const catalog = read('animation/candidates.json');
const clips = catalog.clips.filter(c => c.batch === batch);
assert.ok(clips.length, 'The batch must have real candidates before testing.');
const out = path.join(root, 'output/playwright', batch, 'collection-ui');
fs.mkdirSync(out, { recursive: true });
const report = { batch, artApproval: false, cases: [], errors: [] };
const pass = (name, extra = {}) => report.cases.push({ name, ...extra, passed: true });
const protectedState = { 'patrick.pet.v1': '{"keep":"daily character"}', 'patrick.experience.v1': '{"keep":"daily settings"}' };
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
  const page = await context.newPage();
  page.on('pageerror', e => report.errors.push(e.message));
  try {
    await page.goto('http://127.0.0.1:8765/preview/?review=candidates&group=all&v=20261012-reviewflow1');
    await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready', null, { timeout: 120000 });
    await page.evaluate(values => { for (const [k,v] of Object.entries(values)) localStorage.setItem(k,v); }, protectedState);
    assert.deepEqual(await page.evaluate(() => __patrickPreviewShell.report.clipsFailed), []);
    const options = () => page.locator('#clip-select option').evaluateAll(nodes => nodes.map(n => n.value));
    const newestDay = catalog.clips.map(c => (c.batch || '').slice(0,8)).sort().at(-1);
    const latestBatch = catalog.clips.filter(c => c.batch?.startsWith(newestDay)).at(-1).batch;
    for (const group of ['fitness','playful','new','all']) {
      await page.locator(`[data-candidate-filter="${group}"]`).click();
      const expected = catalog.clips.filter(c => group === 'all' || (group === 'new' ? c.batch === latestBatch : c.batch === `20261012-${group}` || c.collectionTags?.includes(group))).map(c => c.id);
      assert.deepEqual(await options(), expected);
      pass('collection-keeps-all-matching-batches', { group, count: expected.length });
    }
    for (const clip of clips) {
      await page.locator('#clip-select').selectOption(clip.id);
      assert.equal(await page.evaluate(id => __patrickPreviewShell.report.rendering[id].sourceImageHash, clip.id), clip.sha256);
      for (let frame = 0; frame < clip.frameCount; frame++) {
        if (frame) await page.locator('#next-frame').click();
        const painted = await page.locator('#face, #wrist-face').evaluateAll(nodes => nodes.map(c => ({ frame: Number(c.dataset.frame), clip: c.dataset.clip, nonempty: c.getContext('2d').getImageData(0,0,c.width,c.height).data.some((v,i) => i % 4 === 3 && v > 0) })));
        for (const actual of painted) assert.deepEqual(actual, { frame, clip: clip.id, nonempty: true });
      }
      const link = new URL(await page.locator('#size-review-link').getAttribute('href'));
      assert.equal(link.searchParams.get('right'), clip.id);
      assert.equal(link.searchParams.get('review'), 'candidates');
      pass('source-frames-painted-and-size-link', { id: clip.id, frameCount: clip.frameCount });
    }
    const chosen = clips.at(-1);
    await page.locator('#clip-select').selectOption(chosen.id);
    const reviewText = `QA ${batch}: retain frame-level review across collection changes.`;
    await page.locator('#verdict').selectOption('revise');
    await page.locator('#review-note').fill(reviewText);
    await page.locator('[data-candidate-filter="fitness"]').click();
    await page.locator('[data-candidate-filter="all"]').click();
    await page.locator('#clip-select').selectOption(chosen.id);
    assert.equal(await page.locator('#review-note').inputValue(), reviewText);
    await page.reload();
    await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready', null, { timeout: 120000 });
    await page.locator('#clip-select').selectOption(chosen.id);
    const pending = page.waitForEvent('download');
    await page.locator('#export-review').click();
    const exportedPath = path.join(out, 'candidate-review.json');
    await (await pending).saveAs(exportedPath);
    const exported = JSON.parse(fs.readFileSync(exportedPath, 'utf8'));
    assert.equal(exported.clips.length, catalog.clips.length);
    assert.ok(JSON.stringify(exported.clips.find(c => c.asset === chosen.id)).includes(reviewText));
    pass('opinion-survives-filter-reload-export');
    await page.locator('#size-review-link').click();
    await page.waitForFunction(() => window.__patrickSizeReview?.status === 'ready', null, { timeout: 120000 });
    for (const clip of clips) {
      const evidence = await page.evaluate(id => __patrickSizeReview.evidence(id), clip.id);
      assert.equal(evidence.evidenceComplete, true, clip.id);
      assert.equal(evidence.artApproval, false);
      pass('body-evidence-is-complete-and-not-art-approval', { id: clip.id, metrics: evidence.metrics });
    }
    await page.locator('[data-side="1"] .mark-frame').last().click();
    await page.locator('[name="frame-issue"][value="motion"]').check();
    await page.locator('#frame-note').fill(`QA ${batch}: intermediate drawing review`);
    const pendingNote = page.waitForEvent('download');
    await page.locator('#export').click();
    const notePath = path.join(out, 'frame-review.json');
    await (await pendingNote).saveAs(notePath);
    const note = JSON.parse(fs.readFileSync(notePath,'utf8')).frameNotes.find(n => n.clipID === chosen.id);
    assert.equal(note.sourceSha256, chosen.sha256);
    assert.equal(note.artApproval, false);
    pass('frame-feedback-pins-exact-source');
    await page.setViewportSize({width:390,height:844});
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await page.locator('#frame-review').screenshot({path:path.join(out,'frame-review-390.png')});
    for (const [key,value] of Object.entries(protectedState)) assert.equal(await page.evaluate(k => localStorage.getItem(k),key),value);
    assert.deepEqual(report.errors,[]);
    pass('mobile-layout-and-daily-state-preserved');
    report.passed = true;
  } catch (e) { report.passed = false; report.failure = e.stack; process.exitCode = 1; }
  finally {
    await context.close(); await browser.close();
    fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify({batch,passed:report.passed,cases:report.cases.length,errors:report.errors,failure:report.failure}));
  }
})();
