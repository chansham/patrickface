const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const output = process.env.QA_OUTPUT || path.resolve(__dirname, '../output/playwright/20261013-aftercare');
const url = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/ecosystem/aftercare.html?v=20261013-aftercare1';
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const report = { candidateOnly: true, artApproved: false, nativeExecutionVerified: false, noNewAssetClaim: true, cases: [], errors: [], externalRequests: [], geometry: [], playback: [] };
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, reducedMotion: 'no-preference' });
    const page = await context.newPage();
    page.on('pageerror', error => report.errors.push(error.message));
    page.on('request', request => { if (new URL(request.url()).origin !== new URL(url).origin) report.externalRequests.push(request.url()); });
    await page.addInitScript(() => {
      localStorage.setItem('patrick.experience.v1', 'existing-experience'); localStorage.setItem('patrick.review.v1', 'existing-review'); sessionStorage.setItem('existing-session', 'untouched');
      window.__storageCalls = [];
      for (const method of ['getItem', 'setItem', 'removeItem', 'clear']) Object.defineProperty(Storage.prototype, method, { value(...args) { window.__storageCalls.push({ method, args }); throw new Error(`Storage access forbidden: ${method}`); } });
    });
    await page.goto(url); await page.waitForFunction(() => document.documentElement.dataset.aftercare === 'ready');
    assert.equal(await page.evaluate(() => window.__patrickAftercare.error), null);
    assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false);
    assert.equal(await page.evaluate(() => window.__patrickAftercare.playbackCount), 0);
    assert.equal(await page.evaluate(() => window.__patrickAftercare.frame), 0);
    assert.equal(await page.locator('.ending').count(), 3);
    assert.equal(await page.locator('[data-variant=drink]').isDisabled(), true);
    assert.match(await page.locator('[data-variant=drink]').textContent(), /換手待修.*12 格.*未通過/);
    report.cases.push({ name: 'no-autoplay-two-existing-candidates-drink-explicitly-unavailable', passed: true });
    const ids = ['towel', 'rest'], layoutIDs = ['classic', 'bold', 'theater', 'activity'];
    for (const variant of ids) {
      await page.locator(`[data-variant=${variant}]`).click();
      const clip = await page.evaluate(variant => window.__patrickAftercare.clips[variant], variant);
      assert.match(await page.locator('#clip-facts').textContent(), /尚未通過美術確認/);
      assert.match(await page.locator('#review-link').getAttribute('href'), new RegExp(clip.id));
      for (const layout of layoutIDs) {
        await page.locator('#layout').selectOption(layout);
        const scales = [], rects = [];
        for (let frame = 0; frame < clip.frames; frame++) {
          await page.locator('#frame').evaluate((slider, frame) => { slider.value = frame; slider.dispatchEvent(new Event('input', { bubbles: true })); }, frame);
          const measurement = await page.evaluate(() => {
            const state = window.__patrickAftercare, large = document.querySelector('#large-watch'), small = document.querySelector('#small-watch');
            return { clip: state.clips[state.selected].id, layout: state.layoutID, frame: state.frame, ...state.geometry, largeRect: large.dataset.rect, smallRect: small.dataset.rect, smallWidth: parseFloat(getComputedStyle(small).width) };
          });
          assert.equal(measurement.frame, frame); assert.equal(measurement.largeRect, measurement.smallRect); assert.equal(measurement.smallWidth, 200);
          const [x, y, w, h] = measurement.bounds;
          assert.ok(x >= 0 && y >= 0 && x + w <= 832 && y + h <= 992, `${variant}/${layout}/${frame + 1}: source contour fits stage`);
          scales.push(measurement.pixelScale); rects.push(measurement.rect); report.geometry.push(measurement);
        }
        assert.equal(new Set(scales).size, 1, 'same source-pixel scale for entire clip');
        assert.equal(new Set(rects.map(JSON.stringify)).size, 1, 'no per-frame fitting');
        await page.locator('.watch-pair').screenshot({ path: path.join(output, `${variant}-${layout}.png`) });
      }
    }
    report.cases.push({ name: 'all-16-frames-across-four-layouts-64-placements-share-fixed-clip-scale-and-fit-stage', passed: true });
    // Independently render the same contours, then compare their opaque pixels
    // against time/date/info ink and the visible rounded viewport. This checks
    // physical overlap only, not whether the art's proportions are approved.
    const collisionReport = await page.evaluate(async () => {
      const { resource, decodeJSON, loadClip, frameGeometry } = await import('../size-review/render-core.js?v=20261008-acceptance2');
      const { drawLayoutInformation } = await import('../preview/layout-core.js?v=20261012-activity1');
      const repo = new URL('../', location.href), catalog = decodeJSON(await resource('animation/candidates.json', repo)), layouts = decodeJSON(await resource('experience/layouts.json', repo)).layouts, cache = new Map();
      const results = [];
      for (const id of ['sport-towel-first-20261012', 'fitness-tracksuit-first-20261012']) {
        const clip = await loadClip(catalog.clips.find(clip => clip.id === id), repo, cache);
        for (const layout of layouts) {
          const ink = document.createElement('canvas'); ink.width = 832; ink.height = 992; const text = ink.getContext('2d');
          text.textAlign = 'center'; text.textBaseline = 'middle'; text.fillStyle = 'white'; text.font = `${layout.id === 'bold' ? 600 : 480} ${layout.timeFontSize}px "Segoe UI",sans-serif`; text.fillText('18:42', ...layout.timeCenter);
          text.font = `${layout.dateFontSize}px "Microsoft JhengHei",sans-serif`; text.fillText('週二 13 · 收操試演', ...layout.dateCenter);
          drawLayoutInformation(text, layout, { title: '運動倒數', countdown: '00:00', state: '合成完成事件', progress: 1 });
          const timePixels = text.getImageData(0, 0, 832, 992).data;
          for (let frame = 0; frame < clip.frameCount; frame++) {
            const image = document.createElement('canvas'); image.width = 832; image.height = 992; const ctx = image.getContext('2d'), geometry = frameGeometry(clip, frame, catalog.master, layout);
            ctx.drawImage(geometry.source, 0, 0, geometry.source.width, geometry.source.height, ...geometry.rect);
            const pixels = ctx.getImageData(0, 0, 832, 992).data; let overlap = 0, roundedClip = 0, opaque = 0;
            // CSS radius is 22% for both dimensions (elliptical corner).
            const rx = 832 * .22, ry = 992 * .22;
            for (let y = 0; y < 992; y++) for (let x = 0; x < 832; x++) {
              const alpha = (y * 832 + x) * 4 + 3; if (pixels[alpha] < 128) continue; opaque++;
              if (timePixels[alpha] >= 128) overlap++;
              const cx = x < rx ? rx : x > 832 - rx ? 832 - rx : x, cy = y < ry ? ry : y > 992 - ry ? 992 - ry : y;
              if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 > 1) roundedClip++;
            }
            results.push({ id, layout: layout.id, frame, overlap, roundedClip, opaque });
          }
        }
      }
      return results;
    });
    report.pixelChecks = collisionReport;
    assert.ok(collisionReport.every(value => value.opaque > 1000), 'actual colored source pixels, never blank watches');
    assert.ok(collisionReport.every(value => value.roundedClip === 0), 'heads, arms, accessories and feet within rounded viewport');
    assert.ok(collisionReport.every(value => value.overlap === 0), 'no opaque art/time/date/information collision');
    report.cases.push({ name: 'independent-pixel-check-all-64-placements-no-rounded-crop-or-text-overlap', passed: true });
    await page.locator('#layout').selectOption('classic');
    for (const variant of ids) {
      await page.locator(`[data-variant=${variant}]`).click();
      const clip = await page.evaluate(variant => window.__patrickAftercare.clips[variant], variant), started = Date.now();
      await page.locator('#play-review').click(); await page.waitForFunction(() => window.__patrickAftercare.policy.phase === 'done');
      const result = await page.evaluate(() => ({ drawnFrames: window.__patrickAftercare.drawnFrames, phase: window.__patrickAftercare.policy.phase, frame: window.__patrickAftercare.frame, count: window.__patrickAftercare.playbackCount }));
      assert.deepEqual(result.drawnFrames, Array.from({ length: clip.frames }, (_, index) => index));
      assert.equal(result.frame, clip.frames - 1); const elapsedMS = Date.now() - started;
      assert.ok(elapsedMS >= clip.totalMs - 80 && elapsedMS <= clip.totalMs + 1600, `normal 1x timing: ${elapsedMS}/${clip.totalMs}`);
      await page.waitForTimeout(250); assert.equal(await page.evaluate(() => window.__patrickAftercare.playbackCount), result.count);
      report.playback.push({ variant, elapsedMS, plannedMS: clip.totalMs, ...result });
    }
    report.cases.push({ name: 'two-normal-1x-plays-display-every-source-frame-once-and-stop-at-end', passed: true });
    await page.locator('#simulate-complete').click();
    assert.equal(await page.evaluate(() => window.__patrickAftercare.policy.phase), 'offered');
    assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false);
    assert.deepEqual(await page.evaluate(() => window.__patrickAftercare.policy.availableVariants), ['towel', 'rest']);
    await page.locator('#accept-ending').click(); await page.waitForFunction(() => window.__patrickAftercare.policy.phase === 'done');
    const finishedCount = await page.evaluate(() => window.__patrickAftercare.playbackCount);
    await page.locator('#replay-event').click(); assert.equal(await page.evaluate(() => window.__patrickAftercare.policy.phase), 'done');
    assert.equal(await page.evaluate(() => window.__patrickAftercare.playbackCount), finishedCount);
    report.cases.push({ name: 'synthetic-completion-offers-only-explicit-play-and-duplicate-cannot-replay', passed: true });
    for (const action of ['#dismiss', '#new-timer', '#background']) {
      await page.locator('#simulate-complete').click(); await page.locator('#accept-ending').click();
      await page.locator(action).click();
      assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false);
      assert.equal(await page.evaluate(() => window.__patrickAftercare.policy.phase), 'dismissed');
      const stoppedAt = await page.evaluate(() => window.__patrickAftercare.frame);
      if (action === '#background') await page.locator('#background').click();
      await page.locator('#replay-event').click(); await page.waitForTimeout(250);
      assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false); assert.equal(await page.evaluate(() => window.__patrickAftercare.frame), stoppedAt);
    }
    report.cases.push({ name: 'dismiss-new-timer-and-background-interrupt-with-no-foreground-catchup', passed: true });
    await page.locator('#play-review').click(); await page.locator('#quiet').check();
    assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false); assert.equal(await page.locator('#play-review').isDisabled(), true);
    await page.locator('#quiet').uncheck(); assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false);
    await page.emulateMedia({ reducedMotion: 'reduce' }); await page.waitForFunction(() => document.querySelector('#play-review').disabled); assert.equal(await page.locator('#play-review').isDisabled(), true);
    await page.locator('#frame').evaluate(slider => { slider.value = 3; slider.dispatchEvent(new Event('input', { bubbles: true })); }); assert.equal(await page.evaluate(() => window.__patrickAftercare.frame), 3);
    await page.emulateMedia({ reducedMotion: 'no-preference' }); await page.waitForFunction(() => !document.querySelector('#play-review').disabled); assert.equal(await page.evaluate(() => window.__patrickAftercare.playing), false);
    report.cases.push({ name: 'quiet-and-browser-reduced-motion-stop-playback-but-allow-manual-frame-review', passed: true });
    for (const [name, width, height] of [['desktop', 1440, 1100], ['mobile', 390, 844], ['narrow', 320, 720]]) {
      await page.setViewportSize({ width, height }); assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name}: no horizontal overflow`);
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      assert.equal(await page.locator('#small-watch').evaluate(canvas => parseFloat(getComputedStyle(canvas).width)), 200);
      for (const id of ['large-watch', 'small-watch']) {
        const painted = await page.locator(`#${id}`).evaluate(canvas => { const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data; let count = 0; for (let index = 0; index < pixels.length; index += 4) if (pixels[index] > 100 && pixels[index + 1] < pixels[index] * .8) count++; return count; });
        assert.ok(painted > 1000, `${name}: ${id} retains painted character pixels after reflow`);
        await page.locator(`#${id}`).screenshot({ path: path.join(output, `${name}-${id}.png`) });
      }
      await page.evaluate(() => scrollTo(0, 0));
      await page.screenshot({ path: path.join(output, `${name}.png`), fullPage: true });
    }
    report.cases.push({ name: '1440-390-320-responsive-content-size-remains-200px', passed: true });
    assert.deepEqual(await page.evaluate(() => window.__storageCalls), []);
    assert.deepEqual(await page.evaluate(() => ({ local: Object.keys(localStorage).sort(), session: Object.keys(sessionStorage).sort() })), { local: ['patrick.experience.v1', 'patrick.review.v1'], session: ['existing-session'] });
    await page.reload(); await page.waitForFunction(() => document.documentElement.dataset.aftercare === 'ready');
    assert.equal(await page.evaluate(() => window.__patrickAftercare.playbackCount), 0); assert.equal(await page.evaluate(() => window.__patrickAftercare.policy.phase), 'idle');
    assert.deepEqual(await page.evaluate(() => window.__storageCalls), []);
    report.cases.push({ name: 'no-storage-reads-or-writes-existing-experience-and-feedback-preserved', passed: true });
    assert.deepEqual(report.errors, []); assert.deepEqual(report.externalRequests, []);
    report.cases.push({ name: 'no-browser-errors-or-external-requests', passed: true });
    report.passed = true;
  } catch (error) { report.failure = error.stack; throw error; }
  finally { fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); await browser.close(); }
  console.log(`PASS ${report.cases.length} aftercare browser cases`);
})();
