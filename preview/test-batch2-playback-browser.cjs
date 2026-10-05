// Live 1x playback, with frame captures taken from actual render calls.
// These observations do not approve the drawings or replace manual art review.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/batch2-normal-speed');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const runtimeMode = process.env.QA_RUNTIME === '1';
const catalog = JSON.parse(fs.readFileSync(path.join(root, runtimeMode ? 'animation/catalog.json' : 'animation/candidates.json'), 'utf8'));
const requestedIds = process.env.QA_CLIP_IDS?.split(',');
const clips = catalog.clips.filter(clip => requestedIds ? requestedIds.includes(clip.id) : clip.batch === (process.env.QA_BATCH || '20260927-batch2'));
const montageStem = process.env.QA_MONTAGE_STEM || (runtimeMode ? 'runtime-new-actions' : 'six-new-candidates');
assert.ok(clips.length > 0, 'new batch must exist before this live-art check');
fs.mkdirSync(output, { recursive: true });
const report = { startedAt: new Date().toISOString(), url: address + (runtimeMode ? '' : '?review=candidates' + (process.env.QA_GROUP_NEW === '1' ? '&group=new' : '')), speed: 1,
  artQualityApproved: false, clock: 'real browser performance.now; no fake clock', cases: [] };
const escape = value => String(value).replace(/[&<>\"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
const html = (title, cards, columns = 4) => `<!doctype html><meta charset="utf-8"><style>body{margin:0;padding:24px;background:#18151e;color:#eee3ee;font:14px "Segoe UI","Microsoft JhengHei",sans-serif}h1{font-size:23px;font-weight:500;margin:0 0 8px}p{color:#bca8c4;margin:0 0 20px;font-size:12px}.grid{display:grid;grid-template-columns:repeat(${columns},1fr);gap:14px}figure{margin:0;padding:10px;background:#25202b;border:1px solid #4a3a4f;border-radius:15px}img{display:block;width:100%;height:auto;border-radius:12px}figcaption{font-size:12px;line-height:1.6;padding:9px 2px 2px}</style><h1>${escape(title)}</h1><p>實際 1 倍播放擷取 · 全段固定尺度與腳底 · 待修候選，尚未批准</p><div class="grid">${cards.join('')}</div>`;
(async () => {
  const launch = { headless: true };
  if (process.env.CHROMIUM_EXECUTABLE_PATH) launch.executablePath = process.env.CHROMIUM_EXECUTABLE_PATH;
  const browser = await chromium.launch(launch);
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, timezoneId: 'Asia/Hong_Kong', recordVideo: { dir: output, size: { width: 1440, height: 1100 } } });
  const page = await context.newPage(), errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    window.__liveFrames = []; window.__captureLive = false;
    const original = CanvasRenderingContext2D.prototype.drawImage;
    CanvasRenderingContext2D.prototype.drawImage = function (...args) {
      const result = original.apply(this, args);
      if (window.__captureLive && this.canvas.id === 'face') {
        const frame = Number(args[0]?.dataset?.sourceFrame), last = window.__liveFrames.at(-1);
        if (!last || last.frame !== frame) {
          const snapshot = document.createElement('canvas'); snapshot.width = 416; snapshot.height = 496;
          const target = snapshot.getContext('2d'); target.fillStyle = '#070609'; target.fillRect(0, 0, 416, 496);
          original.call(target, this.canvas, 0, 0, 416, 496);
          window.__liveFrames.push({ frame, at: performance.now(), png: snapshot.toDataURL('image/png') });
        }
      }
      return result;
    };
  });
  try {
    await page.goto(report.url, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => ['ready', 'error'].includes(window.__patrickPreviewShell?.report.status));
    assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.status), 'ready');
    if (runtimeMode) await page.locator('#toggle-review').click();
    const optionIds = await page.locator('#clip-select option').evaluateAll(items => items.map(item => item.value));
    assert.ok(clips.every(clip => optionIds.includes(clip.id)), 'all requested clips are available for manual review');
    if (process.env.QA_GROUP_NEW === '1') assert.deepEqual(optionIds, clips.map(clip => clip.id), 'new filter must show exactly the latest requested batch');
    const montage = [];
    for (const clip of clips) {
      const item = { id: clip.id, title: clip.title, frameCount: clip.frameCount, durationMs: clip.durationsMs.reduce((a, b) => a + b, 0), scale: clip.scale, passed: false };
      await page.locator('#clip-select').selectOption(clip.id); await page.locator('#speed').selectOption('1');
      assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.playing), false);
      await page.evaluate(() => { window.__liveFrames = []; window.__captureLive = true; });
      await page.locator('#play').click(); assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.playKind), 'review');
      await page.waitForTimeout(item.durationMs + 250);
      assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.playing), false);
      assert.equal(await page.locator('#face').getAttribute('data-frame'), String(clip.frameCount - 1));
      await page.waitForTimeout(900);
      assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.playing), false);
      assert.equal(await page.locator('#face').getAttribute('data-frame'), String(clip.frameCount - 1));
      const frames = await page.evaluate(() => { window.__captureLive = false; return window.__liveFrames; });
      assert.deepEqual(frames.map(frame => frame.frame), clip.frameIndices || Array.from({ length: clip.frameCount }, (_, i) => i), 'live 1x render visits every frame once and does not restart');
      const cards = []; item.liveFrames = frames.map((frame, index) => {
        const name = `${clip.id}-live-${String(index + 1).padStart(2, '0')}.png`;
        fs.writeFileSync(path.join(output, name), Buffer.from(frame.png.split(',')[1], 'base64'));
        const at = Math.round(frame.at - frames[0].at);
        cards.push(`<figure><img src="${name}"><figcaption>第 ${index + 1} 格 · ${at} ms</figcaption></figure>`);
        return { frame: index + 1, sourceFrame: frame.frame, elapsedMs: at, path: name };
      });
      fs.writeFileSync(path.join(output, `${clip.id}-sequence.html`), html(`${clip.title}｜正常速度畫格紀錄`, cards));
      const representative = Math.min(Math.floor(clip.frameCount / 2), clip.frameCount - 1);
      await page.locator('#frames .frame').nth(representative).click();
      const sample = `${clip.id}-sample.png`; await page.locator('.enlarged .screen').screenshot({ path: path.join(output, sample) });
      montage.push(`<figure><img src="${sample}"><figcaption>${escape(clip.title)}<br>第 ${representative + 1}／${clip.frameCount} 格</figcaption></figure>`);
      item.stoppedAtLastFrame = true; item.autoReplayObserved = false; item.sample = sample; item.passed = true; report.cases.push(item);
      console.log(`PASS live-1x ${clip.id} (${frames.length} frames)`);
    }
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(output, `${montageStem}.html`), html(runtimeMode ? '新充電與投餵｜開發試玩，畫稿待審' : '本批候選｜動作與造型待審', montage, Math.min(3, clips.length)));
    const relativeOutput = path.relative(root, output).split(path.sep).join('/');
    const evidence = await context.newPage(); await evidence.setViewportSize({ width: 1120, height: 1000 });
    for (const clip of clips) { await evidence.goto(new URL(`../${relativeOutput}/${clip.id}-sequence.html`, address).href); await evidence.screenshot({ path: path.join(output, `${clip.id}-sequence.png`), fullPage: true }); }
    await evidence.goto(new URL(`../${relativeOutput}/${montageStem}.html`, address).href);
    await evidence.screenshot({ path: path.join(output, `${montageStem}.png`), fullPage: true });
    report.passed = true;
  } catch (error) { report.error = error.stack; report.passed = false; console.error(error.stack); process.exitCode = 1; }
  finally {
    await page.close(); await context.close(); await page.video().saveAs(path.join(output, `${process.env.QA_MONTAGE_STEM || (runtimeMode ? 'runtime-new-actions' : 'six-clips')}-live-1x.webm`));
    await browser.close(); report.finishedAt = new Date().toISOString(); report.pageErrors = errors;
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
  }
})();
