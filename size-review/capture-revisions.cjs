// Capture the frames actually displayed by the foreground comparison page.
// These screenshots are review evidence, never replacement artwork.
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/20261006-revisions');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/';
const entries = JSON.parse(fs.readFileSync(path.join(root, 'animation/candidates.json'))).clips.filter(clip => clip.comparisonClipId);
const main = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json'))).clips;
const report = { at: new Date().toISOString(), artApproval: false, clips: [] };
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
    const page = await context.newPage();
    for (const clip of entries) {
      const old = main.find(value => value.id === clip.comparisonClipId);
      await page.bringToFront();
      await page.goto(address + `size-review/?review=candidates&left=${old.id}&right=${clip.id}`);
      await page.waitForFunction(() => window.__patrickSizeReview?.status === 'ready');
      await page.locator('#guides').uncheck();
      for (const [side, count] of [[0, old.frameCount], [1, clip.frameCount]]) {
        await page.locator(`#frame-${side}`).fill(String(count - 1));
        await page.locator(`#frame-${side}`).dispatchEvent('input');
      }
      await page.locator('#compare-grid').screenshot({ path: path.join(output, clip.id + '-old-new-last.png') });
      for (const side of [0, 1]) {
        await page.locator(`#frame-${side}`).fill('0');
        await page.locator(`#frame-${side}`).dispatchEvent('input');
      }
      await page.evaluate(() => {
        window.__captureFrames = []; window.__captureAlive = true; window.__captureStart = performance.now();
        function tick() {
          if (!__captureAlive) return;
          const canvas = document.querySelector('[data-side="1"] canvas'), index = Number(canvas.dataset.frame);
          if (!__captureFrames.some(item => item.index === index)) {
            const copy = document.createElement('canvas'); copy.width = 200; copy.height = 238;
            copy.getContext('2d').drawImage(canvas, 0, 0, 200, 238);
            __captureFrames.push({ index, at: performance.now() - __captureStart, png: copy.toDataURL('image/png') });
          }
          requestAnimationFrame(tick);
        }
        tick();
      });
      await page.locator('#play-pair').click();
      await page.waitForFunction(() => !__patrickSizeReview.state.playing, null, { timeout: 15000 });
      const frames = await page.evaluate(() => { __captureAlive = false; return __captureFrames; });
      assert.deepEqual(frames.map(frame => frame.index), Array.from({ length: clip.frameCount }, (_, index) => index));
      // The contact sheet is opened only after live capture, so it cannot throttle the player tab.
      const sheet = await context.newPage(); await sheet.setViewportSize({ width: 960, height: 1100 });
      await sheet.setContent('<html><meta charset="utf-8"><style>body{margin:0;padding:25px;background:#18151e;color:#f5e5ef;font:14px system-ui}h1{font-size:23px}p{color:#c3a8c6;line-height:1.6}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}article{border:1px solid #5d465e;border-radius:12px;padding:8px;background:#261e2d}img{display:block;width:200px;max-width:100%;height:auto;border-radius:17%}small{display:block;color:#bda6c1;margin-top:6px}</style><h1></h1><p>正常 1× 播放時，於每次實際畫格變更擷取。全幅同舞台、固定 200 px 內容寬；不為每格另行放大。這是動作審稿，並非美術批准。</p><div class="grid"></div></html>');
      await sheet.evaluate(({ title, frames }) => {
        document.querySelector('h1').textContent = title + ' · 真實播放逐幀';
        for (const frame of frames) {
          const card = document.createElement('article'), image = document.createElement('img'), label = document.createElement('small');
          image.src = frame.png; label.textContent = `第 ${frame.index + 1} 格 · ${Math.round(frame.at)} ms`;
          card.append(image, label); document.querySelector('.grid').append(card);
        }
      }, { title: clip.title, frames });
      await sheet.screenshot({ path: path.join(output, clip.id + '-live-1x-frames.png'), fullPage: true }); await sheet.close();
      report.clips.push({ id: clip.id, frames: frames.map(({ png, ...rest }) => rest), endedAtLast: true });
      console.log('CAPTURED ' + clip.id + ' ' + frames.length + ' frames');
    }
    await page.bringToFront(); await page.setViewportSize({ width: 390, height: 844 });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: path.join(output, 'revision-mobile.png'), fullPage: true });
    report.passed = true;
  } finally {
    fs.writeFileSync(path.join(output, 'live-capture-report.json'), JSON.stringify(report, null, 2));
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
