const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const output = process.env.QA_OUTPUT || path.resolve(__dirname, '../output/playwright/20261013-health-trends');
const url = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/ecosystem/health-trend.html?v=20261013-health1';
const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, 'health-trend-fixtures.json'), 'utf8'));
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const report = { syntheticOnly: true, nativeExecutionVerified: false, cases: [], errors: [], outboundRequests: [] };
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, reducedMotion: 'reduce' });
    const page = await context.newPage();
    page.on('pageerror', error => report.errors.push(error.message));
    page.on('request', request => { if (new URL(request.url()).origin !== new URL(url).origin) report.outboundRequests.push(request.url()); });
    await page.addInitScript(() => {
      localStorage.setItem('patrick.experience.v1', 'preserve-existing-care');
      localStorage.setItem('patrick.review.v1', 'preserve-existing-feedback');
      sessionStorage.setItem('preserve-session', 'unchanged');
      window.__storageCalls = [];
      for (const method of ['getItem', 'setItem', 'removeItem', 'clear']) {
        Object.defineProperty(Storage.prototype, method, { value(...args) { window.__storageCalls.push(method); throw new Error(`Storage access forbidden in health demo: ${method}`); } });
      }
    });
    await page.goto(url); await page.waitForFunction(() => document.documentElement.dataset.healthTrend === 'ready');
    await page.waitForFunction(() => window.__patrickHealthTrend.art !== 'loading');
    assert.equal(await page.locator('.metric').count(), 3);
    assert.equal(await page.locator('#scenario option').count(), 7);
    assert.equal(await page.locator('input[type=file]').count(), 0);
    assert.equal(await page.locator('form').count(), 0);
    assert.match(await page.locator('.demo-tag').textContent(), /合成資料試演/);
    report.cases.push({ name: 'synthetic-only-no-upload-and-seven-presets', passed: true });
    const ids = await page.locator('#scenario option').evaluateAll(options => options.map(option => option.value));
    for (const id of ids) {
      await page.locator('#scenario').selectOption(id);
      const result = await page.evaluate(() => window.__patrickHealthTrend.results);
      assert.deepEqual(result, fixtures.cases.find(test => test.id === id).expected, `browser fixture ${id}`);
      assert.equal(await page.locator('.metric-chart').count(), result.filter(metric => metric.state === 'ready').length);
      assert.equal(await page.locator('.invitation').getAttribute('data-mode'), 'normal');
    }
    report.cases.push({ name: 'every-visible-preset-matches-independent-shared-fixture', passed: true });
    await page.locator('#scenario').selectOption('mixed-missing');
    assert.match(await page.locator('[data-metric=hrvSDNN] .metric-value').textContent(), /—/);
    assert.match(await page.locator('[data-metric=hrvSDNN] .metric-explanation').textContent(), /不推測授權/);
    assert.equal(await page.locator('[data-metric=sleepHours]').getAttribute('data-state'), 'ready');
    report.cases.push({ name: 'missing-is-not-zero-and-does-not-hide-other-metrics', passed: true });
    await page.locator('#scenario').selectOption('source-change');
    assert.match(await page.locator('[data-metric=sleepHours] .metric-explanation').textContent(), /不沿用舊來源/);
    assert.match(await page.locator('[data-metric=sleepHours] .metric-meta').textContent(), /Watch B/);
    await page.locator('#scenario').selectOption('stale');
    assert.match(await page.locator('[data-metric=sleepHours] .metric-state').textContent(), /最後紀錄已舊/);
    assert.match(await page.locator('[data-metric=sleepHours] .metric-explanation').textContent(), /36 小時/);
    assert.equal(await page.locator('[data-metric=sleepHours] .metric-chart').count(), 0);
    await page.locator('#scenario').selectOption('conflicting-day');
    assert.match(await page.locator('[data-metric=sleepHours] .metric-explanation').textContent(), /互相矛盾/);
    report.cases.push({ name: 'new-source-stale-and-conflicting-data-have-visible-reasons', passed: true });
    for (const feeling of ['tired', 'okay', 'unsure']) {
      await page.locator(`[data-feeling=${feeling}]`).click();
      const selected = await page.evaluate(() => window.__patrickHealthTrend.invitation);
      assert.equal(selected.mode, feeling === 'tired' ? 'gentle' : 'normal');
      for (const id of ids) {
        await page.locator('#scenario').selectOption(id);
        assert.deepEqual(await page.evaluate(() => window.__patrickHealthTrend.invitation), selected);
      }
    }
    assert.match(await page.locator('.device-boundary').textContent(), /沒有修改手機或手錶設定/);
    report.cases.push({ name: 'self-report-alone-chooses-invitation-across-every-data-state', passed: true });
    assert.equal(await page.evaluate(() => window.__patrickHealthTrend.art), 'ready');
    assert.equal(Math.round((await page.locator('.watch').boundingBox()).width), 200);
    assert.match(await page.locator('#art-status').textContent(), /現有起床畫稿.*靜態示意/);
    const coloredPixels = await page.locator('#watch-preview').evaluate(canvas => {
      const { data } = canvas.getContext('2d').getImageData(0, 250, canvas.width, canvas.height - 250);
      let count = 0; for (let index = 0; index < data.length; index += 4) if (data[index] > 100 && data[index + 1] < data[index] * .9 && data[index + 3] > 0) count++;
      return count;
    });
    assert.ok(coloredPixels > 1000, 'Patrick art pixels actually rendered, not just a black watch');
    report.cases.push({ name: 'existing-character-visible-at-200px-no-new-art-claim', passed: true });
    await page.locator('#scenario').selectOption('presentation-ready');
    await page.locator('[data-feeling=tired]').click();
    for (const [name, width, height] of [['desktop', 1440, 1100], ['mobile', 390, 844], ['narrow', 320, 720]]) {
      await page.setViewportSize({ width, height });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name}: no horizontal overflow`);
      assert.equal(Math.round((await page.locator('.watch').boundingBox()).width), 200);
      await page.screenshot({ path: path.join(output, `${name}.png`), fullPage: true });
    }
    report.cases.push({ name: 'desktop-390px-320px-responsive-and-stable-watch-size', passed: true });
    assert.deepEqual(await page.evaluate(() => window.__storageCalls), []);
    const keys = await page.evaluate(() => ({ local: Object.keys(localStorage).sort(), session: Object.keys(sessionStorage).sort() }));
    assert.deepEqual(keys, { local: ['patrick.experience.v1', 'patrick.review.v1'], session: ['preserve-session'] });
    await page.reload(); await page.waitForFunction(() => document.documentElement.dataset.healthTrend === 'ready');
    assert.equal(await page.evaluate(() => window.__patrickHealthTrend.feeling), 'unsure');
    assert.equal(await page.locator('#scenario').inputValue(), 'presentation-ready');
    assert.deepEqual(await page.evaluate(() => window.__storageCalls), []);
    report.cases.push({ name: 'no-storage-access-existing-records-preserved-reset-on-reload', passed: true });
    // Keep seven prior RHR days, but remove one middle day from a synthetic
    // eight-day history. A visible gap must not be drawn as interpolated data.
    const gapFixtures = structuredClone(fixtures);
    const gapCase = gapFixtures.cases.find(test => test.id === 'presentation-ready');
    const originalRHR = gapCase.input.points.filter(point => point.metric === 'restingHeartRate').sort((left, right) => left.dayStartMS - right.dayStartMS);
    const removedStart = originalRHR[3].dayStartMS;
    gapCase.input.points = gapCase.input.points.filter(point => point.metric !== 'restingHeartRate' || point.dayStartMS !== removedStart);
    const gapPage = await context.newPage(); gapPage.on('pageerror', error => report.errors.push(error.message));
    await gapPage.route('**/health-trend-fixtures.json', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(gapFixtures) }));
    await gapPage.goto(url); await gapPage.waitForFunction(() => document.documentElement.dataset.healthTrend === 'ready');
    const gapResult = await gapPage.evaluate(() => window.__patrickHealthTrend.results.find(result => result.metric === 'restingHeartRate'));
    assert.equal(gapResult.state, 'ready'); assert.equal(gapResult.baselineCount, 7);
    const gapChart = gapPage.locator('[data-metric=restingHeartRate] .metric-chart');
    assert.equal(await gapChart.locator('circle').count(), 8);
    assert.equal(await gapChart.locator('line.trend').count(), 6);
    assert.equal(await gapChart.locator('polyline').count(), 0);
    const links = await gapChart.locator('line.trend').evaluateAll(lines => lines.map(line => [Number(line.dataset.fromEndMs), Number(line.dataset.toStartMs)]));
    assert.ok(links.every(([from, to]) => from === to), 'only adjacent day intervals are joined');
    assert.match(await gapChart.getAttribute('aria-label'), /缺日不連線/);
    assert.match(await gapPage.locator('[data-metric=restingHeartRate] .metric-explanation').textContent(), /缺日不連線/);
    assert.match(await gapPage.locator('[data-metric=restingHeartRate] .metric-window').textContent(), /本次區間.*→.*香港時間/);
    assert.match(await gapPage.locator('#aggregation-note').textContent(), /合成範例.*並非真實裝置查詢.*中午至中午.*同一來源也不代表相同測量情境/);
    await gapPage.locator('#metrics').screenshot({ path: path.join(output, 'missing-day-gap.png') });
    await gapPage.close();
    report.cases.push({ name: 'missing-calendar-day-remains-an-unconnected-gap-and-windows-are-explicit', passed: true });
    assert.deepEqual(report.errors, []); assert.deepEqual(report.outboundRequests, []);
    report.cases.push({ name: 'zero-browser-errors-and-no-outbound-requests', passed: true });
    report.passed = true;
  } catch (error) { report.failure = error.stack; throw error; }
  finally { fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); await browser.close(); }
  console.log(`PASS ${report.cases.length} health-trend browser cases`);
})();
