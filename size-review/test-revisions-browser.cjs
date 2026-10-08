const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/20261006-revisions');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/';
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json')));
const candidates = JSON.parse(fs.readFileSync(path.join(root, 'animation/candidates.json')));
const repairAuditPath = 'animation/production-20261006-repair/body-scale-audit.json';
const auditReports = [
  { path: 'animation/production-20261007-completion/body-scale-audit.json', selector: '#completion-audit-source' },
  { path: 'animation/production-20261006-followup/body-scale-audit.json', selector: '#followup-audit-source' },
  { path: repairAuditPath, selector: '#repair-audit-source' },
].map(report => ({ ...report, data: fs.existsSync(path.join(root, report.path)) ? JSON.parse(fs.readFileSync(path.join(root, report.path))) : null }));
const layouts = JSON.parse(fs.readFileSync(path.join(root, 'experience/layouts.json'))).layouts;
const wanted = (process.env.QA_CLIP_IDS || process.env.REVIEW_IDS)?.split(',').map(id => id.trim()).filter(Boolean);
const revisions = candidates.clips.filter(clip => clip.atlas && clip.comparisonClipId && (!wanted || wanted.includes(clip.id)));
const auditFor = clip => {
  for (const report of auditReports) {
    const entry = report.data?.clips.find(entry => entry.catalog === 'candidates' && entry.id === clip.id && entry.sourceSha256 === clip.sha256 && entry.regionsSha256 === clip.frameRegions.sha256);
    if (entry) return { clip, entry, report };
  }
  return null;
};
const selectedAudited = revisions.map(auditFor).filter(Boolean);
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
const report = { startedAt: new Date().toISOString(), artApproval: false, requestedClipIDs: wanted || null, selectedClipIDs: revisions.map(clip => clip.id), cases: [] };
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
      assert.ok(!requests.some(url => auditReports.some(report => url.includes(report.path))));
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
      await page.locator('#note-clip').selectOption('focus');
      assert.equal(await page.locator('#note').inputValue(), oldNote.text);
      result.mainClips = await page.evaluate(() => __patrickSizeReview.clipIDs);
    });
    for (const clip of revisions) await check('actual-old-new-' + clip.id, async result => {
      const previous = catalog.clips.find(value => value.id === clip.comparisonClipId);
      assert.ok(previous, 'Comparison target must be actual main catalog clip');
      assert.ok(!catalog.clips.some(value => value.id === clip.id), 'New candidate must not be a daily runtime clip');
      assert.deepEqual(clip.triggerKinds, ['manual-review'], 'Candidate scenarios remain manual review only');
      await page.goto(address + `size-review/?review=candidates&left=${encodeURIComponent(previous.id)}&right=${encodeURIComponent(clip.id)}`);
      await ready();
      assert.equal(await page.locator('#compare-0').inputValue(), previous.id);
      assert.equal(await page.locator('#compare-1').inputValue(), clip.id);
      assert.equal(await page.evaluate(() => __patrickSizeReview.state.playing), false);
      assert.ok(await page.locator('#revision-banner').isVisible());
      assert.equal(await page.locator('#outfit-grid .card').count(), 11);
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
      await page.locator('#guides').uncheck();
      const verifiedAudit = auditFor(clip), audited = verifiedAudit?.entry;
      assert.ok(audited, 'Selected revision requires a matching checked audit entry, including explicit unknown metrics');
      result.auditPath = verifiedAudit.report.path;
      const regions = JSON.parse(fs.readFileSync(path.join(root, clip.frameRegions.path)));
      const sourceScale = 665.6 * clip.scale / regions.canvas.width;
      const expectedMetrics = index => {
        const sourceIndex = clip.frameIndices?.[index] ?? index;
        const source = audited?.frames.find(frame => frame.sourceFrame === sourceIndex)?.source;
        return ['faceWidth', 'eyeSeparation', 'eyeToFoot'].map(key => Number.isFinite(source?.[key]) ? `${(source[key] * sourceScale * 200 / 832).toFixed(1)} px` : '未能量測');
      };
      assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(), expectedMetrics(0));
      assert.match(await page.locator('[data-side="1"] .measurement-source').textContent(), /改稿量測/);
      assert.match(await page.locator('[data-side="0"] .measurement-source').textContent(), /舊版量測快照/);
      if (audited && expectedMetrics(0).every(value => value !== '未能量測')) {
        assert.ok(expectedMetrics(0).every(value => value !== '未能量測'), 'Verified first frame must show all three metrics');
        await page.locator('#landmarks').check();
        const first = audited.frames[0].source, geometry = await page.evaluate(id => __patrickSizeReview.geometry(id, 0, 'classic'), clip.id);
        const line = JSON.parse(await page.locator('[data-side="1"] canvas').first().getAttribute('data-foot-line'));
        const [dx, dy] = regions.frames[0].translation;
        const expected = first.eyeToFootPoints.map(([x, y]) => [geometry.rect[0] + (x + dx) * sourceScale, geometry.rect[1] + (y + dy) * sourceScale]);
        line.forEach((point, i) => point.forEach((value, axis) => assert.ok(Math.abs(value - expected[i][axis]) < 1e-7)));
        assert.ok(Math.abs((line[1][1] - line[0][1]) / sourceScale - first.eyeToFoot) < 1e-7);
        if (clip.id === 'chef-repair-20261006') assert.ok(geometry.anchor[1] - line[1][1] > 50, 'True feet end above the cushion render anchor');
        result.measuredFootLine = line;
        await page.locator('#compare-grid').screenshot({ path: path.join(output, clip.id + '-measured-first.png') });
        await page.locator('#landmarks').uncheck();
      }
      await page.locator('#compare-grid').screenshot({ path: path.join(output, clip.id + '-old-new-first.png') });
      result.geometry = await page.evaluate(id => {
        const select = document.querySelector('#frame-1');
        return Array.from({ length: Number(select.max) + 1 }, (_, index) => __patrickSizeReview.geometry(id, index, 'classic'));
      }, clip.id);
      assert.equal(result.geometry.length, clip.frameCount);
      assert.equal(new Set(result.geometry.map(value => JSON.stringify(value.rect))).size, 1);
      assert.equal(new Set(result.geometry.map(value => value.pixelScale)).size, 1);
      assert.equal(new Set(result.geometry.map(value => JSON.stringify(value.anchor))).size, 1);
      result.fourLayouts = await page.evaluate(({ id, count, layouts }) => {
        const ctx = document.createElement('canvas').getContext('2d');
        const textBounds = (text, center, font) => {
          ctx.font = font; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
          const m = ctx.measureText(text);
          return [center[0] - m.actualBoundingBoxLeft, center[1] - m.actualBoundingBoxAscent,
            m.actualBoundingBoxLeft + m.actualBoundingBoxRight, m.actualBoundingBoxAscent + m.actualBoundingBoxDescent];
        };
        return layouts.map(layout => ({ id: layout.id, zones: [
          { kind: 'time', bounds: textBounds('10:10', layout.timeCenter, `${layout.id === 'bold' ? 600 : 480} ${layout.timeFontSize}px "Segoe UI", sans-serif`) },
          { kind: 'date', bounds: textBounds('10/6（週二）', layout.dateCenter, `${layout.dateFontSize}px "Microsoft JhengHei", sans-serif`) },
          ...(layout.informationRect ? [{ kind: 'information', bounds: layout.informationRect }] : []),
        ], frames: Array.from({ length: count }, (_, i) => __patrickSizeReview.geometry(id, i, layout.id)) }));
      }, { id: clip.id, count: clip.frameCount, layouts });
      for (const layout of result.fourLayouts) for (const [index, frame] of layout.frames.entries()) {
        const [x, y, w, h] = frame.bounds;
        assert.ok(w > 0 && h > 0 && x >= 0 && y >= 0 && x + w <= 832 && y + h <= 992,
          `${clip.id} frame ${index + 1} ${layout.id} visible core outside stage: ${frame.bounds}`);
        for (const zone of layout.zones) {
          const [zx, zy, zw, zh] = zone.bounds;
          assert.ok(x + w <= zx || x >= zx + zw || y + h <= zy || y >= zy + zh,
            `${clip.id} frame ${index + 1} ${layout.id} overlaps ${zone.kind}: ${JSON.stringify({ bounds: frame.bounds, zone: zone.bounds })}`);
        }
      }
      for (let index = 0; index < clip.frameCount; index++) {
        await page.locator('#frame-1').fill(String(index)); await page.locator('#frame-1').dispatchEvent('input');
        assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(), expectedMetrics(index), 'Unavailable or occluded metrics must stay empty');
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
      await page.locator('[data-tab="layouts"]').click(); await page.locator('#layout-clip').selectOption(clip.id);
      const middle = Math.floor((clip.frameCount - 1) / 2);
      await page.locator('#layout-frame').fill(String(middle)); await page.locator('#layout-frame').dispatchEvent('input');
      const viewPairs = await page.locator('#layout-grid canvas').evaluateAll(nodes => nodes.map(node => ({ layout: node.dataset.layout, frame: node.dataset.frame, rect: node.dataset.rect, scale: node.dataset.pixelScale })));
      for (const layout of layouts) {
        const views = viewPairs.filter(view => view.layout === layout.id); assert.equal(views.length, 2);
        assert.equal(views[0].frame, String(middle)); assert.deepEqual(views[0], views[1]);
      }
      await page.locator('#layout-grid').screenshot({ path: path.join(output, clip.id + '-four-layouts.png') });
    });
    if (selectedAudited.length) await check('repair-audit-hashes-fail-closed-without-old-metric-fallback', async result => {
      result.rejected = [];
      for (const [index, checked] of selectedAudited.entries()) {
        const { clip, report: auditReport } = checked;
        const url = new URL(auditReport.path, address).href;
        const id = clip.id, field = index % 2 ? 'regionsSha256' : 'sourceSha256';
        const altered = structuredClone(auditReport.data), target = altered.clips.find(entry => entry.id === id);
        target[field] = '0'.repeat(64);
        await page.route(url, route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(altered) }));
        await page.goto(address + `size-review/?review=candidates&left=${clip.comparisonClipId}&right=${id}`); await ready();
        assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(), ['未能量測', '未能量測', '未能量測']);
        assert.match(await page.locator('[data-side="1"] .measurement-source').textContent(), /版本不符/);
        assert.notEqual(await page.locator('[data-side="0"] .measurement-row strong').first().textContent(), '未能量測');
        await page.locator('#guides').uncheck();
        const before = await page.locator('[data-side="1"] canvas').first().evaluate(canvas => canvas.toDataURL());
        await page.locator('#landmarks').check();
        assert.equal(await page.locator('[data-side="1"] canvas').first().evaluate(canvas => canvas.toDataURL()), before, 'A stale report must not draw any measurement pixels');
        assert.equal(await page.locator('[data-side="1"] canvas').first().getAttribute('data-foot-line'), '');
        await page.unroute(url); result.rejected.push({ id, field, auditPath: auditReport.path });
      }
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
    });
    if (selectedAudited.length) await check('repair-audit-unavailable-isolated-from-old-snapshot', async result => {
      const { clip, report: auditReport } = selectedAudited[0];
      const url = new URL(auditReport.path, address).href;
      await page.route(url, route => route.fulfill({ status: 404, body: 'Unavailable fixture' }));
      await page.goto(address + `size-review/?review=candidates&left=${clip.comparisonClipId}&right=${clip.id}`); await ready();
      assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(), ['未能量測', '未能量測', '未能量測']);
      assert.notEqual(await page.locator('[data-side="0"] .measurement-row strong').first().textContent(), '未能量測');
      assert.match(await page.locator(auditReport.selector).textContent(), /未讀入/);
      result.sources = await page.evaluate(() => __patrickSizeReview.auditSources);
      assert.equal(result.sources.find(source => source.path === auditReport.path).loaded, false);
      assert.equal(result.sources.find(source => source.path.includes('/production-20261006-scale/')).loaded, true);
      await page.unroute(url);
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), seeded);
      // Leave the real report loaded for the following persistence check.
      await page.reload(); await ready();
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
    const latestBatch = [...new Set(candidates.clips.map(clip => clip.batch).filter(Boolean))]
      .sort((a, b) => a.localeCompare(b, 'en', { numeric: true })).at(-1);
    if (revisions.every(clip => clip.batch === latestBatch)) await check('main-candidate-new-group-is-selected-batch-and-manual-only', async result => {
      const before = await page.evaluate(() => Object.fromEntries(Object.entries(localStorage)));
      await page.goto(address + 'preview/?review=candidates&group=new');
      await page.waitForFunction(() => ['ready', 'error'].includes(window.__patrickPreviewShell?.report.status));
      const shell = await page.evaluate(() => __patrickPreviewShell.report);
      assert.equal(shell.status, 'ready', shell.lastError);
      assert.equal(await page.locator('[data-candidate-filter="new"]').getAttribute('aria-pressed'), 'true');
      const ids = await page.locator('#clip-select option').evaluateAll(nodes => nodes.map(node => node.value));
      assert.deepEqual(ids.sort(), revisions.map(clip => clip.id).sort());
      for (const clip of revisions) {
        await page.locator('#clip-select').selectOption(clip.id);
        assert.equal(await page.locator('#face').getAttribute('data-clip'), clip.id);
        assert.equal(await page.evaluate(() => __patrickPreviewShell.report.playing), false);
        await page.locator('#next-frame').click();
        await page.waitForTimeout(300);
        assert.equal(await page.evaluate(() => __patrickPreviewShell.report.playing), false);
      }
      assert.deepEqual(await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))), before);
      await page.screenshot({ path: path.join(output, 'main-candidate-latest-batch.png'), fullPage: true });
      result.clipIDs = ids; result.latestBatch = latestBatch;
    });
    assert.deepEqual(errors, []);
  } finally {
    report.errors = errors; report.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); await browser.close();
  }
  if (report.cases.some(result => !result.passed)) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
