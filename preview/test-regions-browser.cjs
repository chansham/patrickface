// Real atlases in disposable contexts. This validates extraction/rendering,
// not animation drawing quality or the artist's intended fringe assignment.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/contour-after');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
const catalogs = [read('animation/catalog.json'), read('animation/candidates.json')];
const requestedClipIDs = process.env.QA_CLIP_IDS?.split(',');
if (requestedClipIDs) assert.ok(requestedClipIDs.every(id => catalogs.some(catalog => catalog.clips.some(clip => clip.id === id))), 'each requested clip must exist');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const report = { startedAt: new Date().toISOString(), artQualityApproved: false,
  scope: 'Real source pixels, contour ownership, shared render canvas, fixed scale/foot anchor, failure isolation and old review preservation.', cases: [] };
fs.mkdirSync(output, { recursive: true });
async function ready(page, candidates = true) {
  await page.goto(address + (candidates ? '?review=candidates' : ''), { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => ['ready', 'error'].includes(window.__patrickPreviewShell?.report.status));
  const state = await page.evaluate(() => window.__patrickPreviewShell.report);
  assert.equal(state.status, 'ready', state.lastError); return state;
}
async function capture(page, id, frame) {
  const stem = `${id}-frame-${frame + 1}`;
  await page.locator('.enlarged .screen').screenshot({ path: path.join(output, `${stem}-screen.png`) });
  await page.locator('#face').screenshot({ path: path.join(output, `${stem}-stage.png`) });
  await page.screenshot({ path: path.join(output, `${stem}-page.png`), fullPage: true });
}
(async () => {
  const launch = { headless: true };
  if (process.env.CHROMIUM_EXECUTABLE_PATH) launch.executablePath = process.env.CHROMIUM_EXECUTABLE_PATH;
  const browser = await chromium.launch(launch);
  async function test(name, body) {
    if (process.env.QA_CASE_FILTER && !new RegExp(process.env.QA_CASE_FILTER).test(name)) return;
    const item = { name, passed: false }, context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, timezoneId: 'Asia/Hong_Kong', acceptDownloads: true });
    const page = await context.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.addInitScript(() => {
        window.__regionFrames = new Map(); window.__regionAtlases = new Map(); window.__targets = new WeakMap();
        const draw = CanvasRenderingContext2D.prototype.drawImage;
        CanvasRenderingContext2D.prototype.drawImage = function (...args) {
          const id = this.canvas.dataset.regionClip;
          if (id) {
            if (!window.__regionFrames.has(id)) window.__regionFrames.set(id, []);
            window.__regionFrames.get(id)[Number(this.canvas.dataset.sourceFrame)] = this.canvas;
            window.__regionAtlases.set(id, args[0]);
          } else if (args[0]?.dataset?.regionClip) window.__targets.set(this.canvas, { source: args[0], rect: args.slice(1) });
          return draw.apply(this, args);
        };
      });
      await page.clock.install({ time: new Date('2026-09-27T06:00:00Z') });
      await page.clock.pauseAt(new Date('2026-09-27T06:01:00Z'));
      await body(page, item); assert.deepEqual(errors, []); item.passed = true;
      console.log(`PASS ${name}`);
    } catch (error) {
      item.error = error.stack; item.pageErrors = errors; console.error(`FAIL ${name}: ${error.message}`);
      await page.screenshot({ path: path.join(output, `${name}-failure.png`), fullPage: true, timeout: 3000 }).catch(() => {});
    } finally { report.cases.push(item); await context.close(); }
  }
  try {
    await test('all-real-contours-source-pixels-ownership-and-three-views', async (page, item) => {
      item.clips = [];
      for (let catalogIndex = 0; catalogIndex < catalogs.length; catalogIndex++) {
        const catalog = catalogs[catalogIndex];
        const selected = catalog.clips.filter(clip => clip.frameRegions && (!requestedClipIDs || requestedClipIDs.includes(clip.id)));
        if (!selected.length) continue;
        await ready(page, catalogIndex === 1);
        for (const clip of selected) {
          const bytes = fs.readFileSync(path.join(root, clip.frameRegions.path));
          assert.equal(hash(bytes), clip.frameRegions.sha256); const metadata = JSON.parse(bytes);
          await page.locator('#clip-select').selectOption(clip.id);
          assert.match(await page.locator('#clip-state').textContent(), /輪廓分離・固定腳底/);
          assert.match(await page.locator('#review-revision').textContent(), /既有意見保留/);
          const extraction = await page.evaluate(({ clip, metadata }) => {
            const atlas = window.__regionAtlases.get(clip.id), frames = window.__regionFrames.get(clip.id);
            const source = document.createElement('canvas'); source.width = clip.width; source.height = clip.height;
            const context = source.getContext('2d'); context.drawImage(atlas, 0, 0);
            const pixels = context.getImageData(0, 0, source.width, source.height).data;
            // Independent per-pixel copy is the oracle; production uses a clip path.
            const labels = new Uint16Array(clip.width * clip.height); let overlaps = 0;
            metadata.frames.forEach((frame, index) => {
              for (const [y, ...runs] of frame.rows) for (let i = 0; i < runs.length; i += 2) for (let x = runs[i]; x < runs[i + 1]; x++) {
                if (labels[y * clip.width + x]) overlaps++; labels[y * clip.width + x] = index + 1;
              }
            });
            let unassigned = 0; for (let i = 0; i < labels.length; i++) if (pixels[4 * i + 3] && !labels[i]) unassigned++;
            const observations = metadata.frames.map((frame, index) => {
              const canvas = frames[index], actual = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
              const expected = new Uint8ClampedArray(actual.length), [dx, dy] = frame.translation;
              let expectedCore = 0, nonzero = 0, neighborLabels = 0, missingCore = 0, mismatchChannels = 0;
              for (const [y, ...runs] of frame.rows) for (let i = 0; i < runs.length; i += 2) for (let x = runs[i]; x < runs[i + 1]; x++) {
                const src = 4 * (y * clip.width + x), dst = 4 * ((y + dy) * canvas.width + x + dx);
                expected.set(pixels.subarray(src, src + 4), dst); if (pixels[src + 3] >= 128) expectedCore++;
              }
              for (let offset = 0; offset < actual.length; offset += 4) {
                const pixel = offset / 4, x = pixel % canvas.width - dx, y = Math.floor(pixel / canvas.width) - dy;
                if (actual[offset + 3]) {
                  nonzero++; if (x < 0 || y < 0 || x >= clip.width || y >= clip.height || labels[y * clip.width + x] !== index + 1) neighborLabels++;
                }
                if (expected[offset + 3] >= 128 && actual[offset + 3] !== expected[offset + 3]) missingCore++;
                for (let c = 0; c < 4; c++) if (actual[offset + c] !== expected[offset + c]) mismatchChannels++;
              }
              return { frame: index + 1, width: canvas.width, height: canvas.height, expectedCore, nonzero, neighborLabels, missingCore, mismatchChannels,
                foot: [frame.anchorSource[0] + dx, frame.anchorSource[1] + dy], sourceBounds: frame.sourceBounds };
            });
            return { overlaps, unassigned, observations };
          }, { clip, metadata });
          assert.equal(extraction.overlaps, 0); assert.equal(extraction.unassigned, 0);
          for (const frame of extraction.observations) {
            assert.equal(frame.width, metadata.canvas.width); assert.equal(frame.height, metadata.canvas.height);
            assert.equal(frame.neighborLabels, 0, `${clip.id} frame ${frame.frame}: neighbor pixels leaked`);
            assert.equal(frame.missingCore, 0); assert.equal(frame.mismatchChannels, 0, `${clip.id} frame ${frame.frame}: source pixels changed`);
            assert.ok(frame.expectedCore >= metadata.frames[frame.frame - 1].diagnostics.corePixelCount);
            assert.deepEqual(frame.foot, metadata.canvas.anchorPixels);
          }
          let destination; const views = [];
          for (let frame = 0; frame < clip.frameCount; frame++) {
            await page.locator('#frames .frame').nth(frame).click();
            const observed = await page.evaluate(({ clip, frame, metadata }) => {
              const a = document.querySelector('#face'), b = document.querySelector('#wrist-face'), t = document.querySelectorAll('#frames .frame canvas')[frame];
              const targets = [a, b, t].map(canvas => window.__targets.get(canvas));
              const sourceIndex = clip.frameIndices?.[frame] ?? frame;
              const shared = targets.every(target => target.source === window.__regionFrames.get(clip.id)[sourceIndex]);
              const p = a.getContext('2d').getImageData(0, 0, a.width, a.height).data, q = b.getContext('2d').getImageData(0, 0, b.width, b.height).data;
              let same = true, minY = a.height, maxY = -1; for (let i = 0; i < p.length; i += 4) {
                if (p[i + 3] >= 128) { const y = Math.floor(i / 4 / a.width); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
                if (same) for (let c = 0; c < 4; c++) if (p[i + c] !== q[i + c]) same = false;
              }
              const rect = targets[0].rect, pixelScale = rect[6] / metadata.canvas.width;
              return { shared, same, rect, minY, maxY, smallWidth: b.getBoundingClientRect().width, pixelScale,
                foot: [rect[4] + metadata.canvas.anchorPixels[0] * pixelScale, rect[5] + metadata.canvas.anchorPixels[1] * pixelScale] };
            }, { clip, frame, metadata });
            assert.equal(observed.shared, true, 'watch/200px/thumbnail must use the identical extracted frame object'); assert.equal(observed.same, true);
            assert.ok(Math.abs(observed.smallWidth - 200) < .1);
            assert.deepEqual(observed.rect.slice(0, 4), [0, 0, metadata.canvas.width, metadata.canvas.height]);
            if (destination) assert.deepEqual(observed.rect.slice(4), destination); else destination = observed.rect.slice(4);
            assert.ok(Math.abs(observed.pixelScale - 665.6 * clip.scale / metadata.canvas.width) < 1e-9, 'all frames must retain the catalog whole-clip scale; never refit each contour');
            assert.ok(Math.abs(observed.foot[0] - (83.2 + 665.6 * catalog.master.anchorNormalized[0])) < 1e-6);
            assert.ok(Math.abs(observed.foot[1] - (248 + 665.6 * catalog.master.anchorNormalized[1])) < 1e-6);
            assert.ok(observed.minY >= Math.floor(992 * .24), `${clip.id} frame ${frame + 1} enters time zone`);
            assert.ok(observed.maxY <= Math.ceil(992 * .93), `${clip.id} frame ${frame + 1} crosses bottom line`);
            views.push({ frame: frame + 1, minY: observed.minY, maxY: observed.maxY, pixelScale: observed.pixelScale, foot: observed.foot });
            if (['candidate-yawn16', 'focus-candidate'].includes(clip.id) && [8, 9].includes(frame)) await capture(page, clip.id, frame);
          }
          item.clips.push({ id: clip.id, imageHash: clip.sha256, regionsHash: clip.frameRegions.sha256, canvas: metadata.canvas,
            destination, extraction, views, artQualityApproved: false });
        }
      }
    });
    for (const failure of ['404', 'wrong-hash', 'wrong-source']) await test(`sidecar-${failure}-never-falls-back-to-grid`, async (page, item) => {
      const catalog = structuredClone(catalogs[1]), clip = catalog.clips[0];
      if (failure === 'wrong-source') {
        const metadata = read(clip.frameRegions.path); metadata.source.sha256 = '0'.repeat(64);
        const body = JSON.stringify(metadata); clip.frameRegions.sha256 = hash(body);
        await page.route(`**/${clip.frameRegions.path}*`, route => route.fulfill({ contentType: 'application/json', body }));
        await page.route('**/animation/candidates.json*', route => route.fulfill({ json: catalog }));
      } else await page.route(`**/${clip.frameRegions.path}*`, route => route.fulfill(failure === '404' ? { status: 404, body: 'Not found' } : { contentType: 'application/json', body: '{}' }));
      const state = await ready(page); assert.equal(state.clipsLoaded.length, catalog.clips.length - 1); assert.equal(state.clipsFailed[0].id, clip.id);
      await page.locator('#clip-select').selectOption(clip.id); assert.equal(await page.locator('#frames .frame').count(), 0); assert.equal(await page.locator('#play').isDisabled(), true);
      const painted = await page.locator('#face').evaluate(canvas => canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data.some(value => value));
      assert.equal(painted, false); assert.match(await page.locator('#status').textContent(), /輪廓資料/);
      await page.locator('#clip-select').selectOption(catalog.clips[1].id); assert.equal(await page.locator('#frames .frame').count(), catalog.clips[1].frameCount);
      item.failure = state.clipsFailed; item.noGridFallback = true;
    });
    await test('review-opinions-survive-rendering-revision-with-explicit-provenance', async (page, item) => {
      const [known, unknown] = catalogs[1].clips;
      const key = clip => `patrick.animation-candidate-review.${clip.id}.v${clip.version}.${clip.sha256}`;
      const make = (clip, rendering) => ({ asset: clip.id, version: clip.version, sha256: clip.sha256, frames: { 8: 'revise' }, note: '原等格裁切意見仍保留', ...(rendering ? { rendering } : {}) });
      const oldRendering = { method: 'regular-grid', renderingRevision: 'legacy-grid-v1' };
      const seeded = { [key(known)]: JSON.stringify(make(known, oldRendering)), [key(unknown)]: JSON.stringify(make(unknown)) };
      await page.addInitScript(values => { for (const [key, value] of Object.entries(values)) if (!localStorage.getItem(key)) localStorage.setItem(key, value); }, seeded);
      await ready(page); assert.match(await page.locator('#review-note').inputValue(), /原等格/);
      await page.locator('#frames .frame').nth(8).click(); assert.equal(await page.locator('#verdict').inputValue(), 'revise');
      for (const [name, value] of Object.entries(seeded)) assert.equal(await page.evaluate(key => localStorage.getItem(key), name), value, 'reading does not rewrite provenance');
      const pending = page.waitForEvent('download'); await page.locator('#export-review').click(); const download = await pending;
      const target = path.join(output, 'rendering-review-export.json'); await download.saveAs(target); const exported = JSON.parse(fs.readFileSync(target, 'utf8'));
      const previous = exported.clips.find(clip => clip.asset === known.id), noPrevious = exported.clips.find(clip => clip.asset === unknown.id);
      assert.deepEqual(previous.rendering, oldRendering); assert.deepEqual(previous.savedReviewRendering, oldRendering);
      assert.equal(previous.currentRendering.method, 'contour-runs'); assert.equal(previous.currentRendering.regionsHash, known.frameRegions.sha256);
      assert.equal(noPrevious.savedReviewRendering, 'unknown'); assert.equal(Object.hasOwn(noPrevious, 'rendering'), false);
      assert.equal(noPrevious.sections.action.frames[8], 'revise'); item.export = target;
    });
  } finally { await browser.close(); report.finishedAt = new Date().toISOString(); fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); }
  if (report.cases.some(item => !item.passed)) process.exitCode = 1;
})();
