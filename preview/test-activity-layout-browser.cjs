// Actual source alpha + product DOM. This is layout evidence, never art approval.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..'), output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/20261012-activity-layout');
const base = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/';
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
const catalogs = ['animation/catalog.json', 'animation/candidates.json'].map(name => ({ name, ...read(name) }));
const layout = read('experience/layouts.json').layouts.find(x => x.id === 'activity');
const before = { ...layout, characterTransform: [.56, 8, 354], informationRect: [476, 350, 310, 470] };
const report = { date: new Date().toISOString(), artApproval: false, nativeCompiled: false, before, after: layout, cases: [] };
fs.mkdirSync(output, { recursive: true });
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, timezoneId: 'Asia/Hong_Kong' });
  let page = await context.newPage();
  async function test(name, action) {
    const item = { name, passed: false }; report.cases.push(item);
    try { await action(item); item.passed = true; console.log('PASS ' + name); }
    catch (error) { item.error = error.stack; console.error('FAIL ' + name + ': ' + error.message); await page.screenshot({ path: path.join(output, name + '-failure.png'), fullPage: true }).catch(() => {}); }
  }
  try {
    await test('all-current-original-frames-fixed-scale-and-date-footer-clearance', async item => {
      await page.goto(base + 'experience/', { waitUntil: 'domcontentloaded' });
      item.frames = await page.evaluate(async ({ catalogs, layout, before, base }) => {
        const { loadClip, frameGeometry, strongBounds } = await import(base + 'size-review/render-core.js?v=20261012-activity1');
        const { drawLayoutInformation } = await import(base + 'preview/layout-core.js?v=20261012-activity1');
        const cache = new Map(), clips = new Map(), frames = [];
        for (const catalog of catalogs) for (const raw of catalog.clips.filter(c => c.atlas && c.frameRegions)) {
          const clip = await loadClip(raw, new URL(base), cache);
          // Check original atlas positions too, including currently excluded animation frames.
          const all = { ...clip, frameIndices: clip.metadata.frames.map((_, i) => i) };
          clips.set(raw.id, { clip: all, master: catalog.master });
          for (let index = 0; index < all.frameIndices.length; index++) {
            const after = frameGeometry(all, index, catalog.master, layout), old = frameGeometry(all, index, catalog.master, before);
            const rasterHeight = geometry => {
              const canvas = document.createElement('canvas'); canvas.width = 200; canvas.height = 239;
              canvas.getContext('2d').drawImage(geometry.source, ...geometry.rect.map(value => value * 200 / 832));
              const bounds = strongBounds(canvas); canvas.width = canvas.height = 0; return bounds[3];
            };
            frames.push({ catalog: catalog.name, id: raw.id, atlas: raw.atlas, sourceHash: raw.sha256,
              regionsHash: raw.frameRegions.sha256, frame: index + 1, before: old.bounds, after: after.bounds,
              rect: after.rect, anchor: after.anchor, pixelScale: after.pixelScale,
              beforeHeight200: rasterHeight(old), afterHeight200: rasterHeight(after) });
          }
        }
        window.activityComparison = { clips, async show(ids, index = 0) {
          document.body.innerHTML = '<style>body{margin:24px;background:#18151e;color:#eee;font:14px system-ui}.grid{display:flex;gap:20px}canvas{width:200px;border-radius:25px;background:black}h1{font-size:22px}h2{font-size:14px}</style><h1>運動資訊 · 同一來源、同一格、200px內容舞台</h1><p>舊版左欄 → 新版中央角色；原圖與整段來源倍率沒有改動。</p><main></main>';
          for (const id of ids) {
            const { clip, master } = clips.get(id), frame = Math.min(index, clip.frameIndices.length - 1);
            const section = document.createElement('section'); section.innerHTML = `<h2>${clip.title} · 第${frame + 1}格</h2><div class="grid"></div>`; document.querySelector('main').append(section);
            for (const [label, spec] of [['調整前', before], ['目前', layout]]) {
              const box = document.createElement('article'), canvas = document.createElement('canvas'); canvas.width = 832; canvas.height = 992;
              const ctx = canvas.getContext('2d'), g = frameGeometry(clip, frame, master, spec);
              ctx.fillStyle = '#070609'; ctx.fillRect(0, 0, 832, 992); ctx.drawImage(g.source, ...g.rect);
              ctx.fillStyle = '#faf6fb'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = '500 120px "Segoe UI"'; ctx.fillText('10:10', ...spec.timeCenter);
              ctx.fillStyle = '#ab99b5'; ctx.font = '40px "Microsoft JhengHei"'; ctx.fillText('10/12（週一）', ...spec.dateCenter);
              if (label === '目前') drawLayoutInformation(ctx, spec, { title: '跑步', countdown: '04:58', state: '一起慢慢來', progress: .2 });
              else { const [x,y] = spec.informationRect; ctx.textAlign='left';ctx.font='42px "Microsoft JhengHei"';ctx.fillText('跑步',x+24,y+100);ctx.font='72px "Segoe UI"';ctx.fillText('04:58',x+24,y+180);ctx.font='38px "Microsoft JhengHei"';ctx.fillText('一起慢慢來',x+24,y+255);ctx.font='42px "Microsoft JhengHei"';ctx.fillText('飽足 60%',x+24,y+360); }
              box.append(canvas, document.createTextNode(label)); section.querySelector('.grid').append(box);
            }
          }
        } };
        return frames;
      }, { catalogs, layout, before, base });
      const grouped = new Map();
      for (const frame of item.frames) {
        const [x,y,w,h] = frame.after;
        assert.ok(x >= 0 && y >= 234 && x+w <= 832 && y+h < layout.informationRect[1], `${frame.id}/${frame.frame} clips or overlaps date/footer: ${frame.after}`);
        const key = frame.catalog + frame.id, previous = grouped.get(key);
        if (previous) { assert.deepEqual(frame.rect, previous.rect); assert.deepEqual(frame.anchor, previous.anchor); assert.equal(frame.pixelScale, previous.pixelScale); }
        grouped.set(key, frame); assert.ok(frame.afterHeight200 > frame.beforeHeight200, frame.id + ' visibly grows');
      }
      item.sourcePositions = item.frames.length;
      item.uniqueSourceFrames = new Set(item.frames.map(f => f.sourceHash + ':' + f.regionsHash + ':' + f.frame)).size;
      item.uniqueAtlases = new Set(item.frames.map(f => f.sourceHash)).size;
      item.sourceVariants = grouped.size;
      item.minimumDateGap = Math.min(...item.frames.map(f => f.after[1])) - 234;
      item.minimumFooterGap = layout.informationRect[1] - Math.max(...item.frames.map(f => f.after[1] + f.after[3]));
      for (const id of ['running-first-20261006', 'exercise-repair-20261006', 'charging-cozy-20261007']) {
        const frames = item.frames.filter(f => f.id === id);
        (item.comparison ||= []).push({ id, frames: frames.length,
          beforeRasterHeight200: [Math.min(...frames.map(f => f.beforeHeight200)), Math.max(...frames.map(f => f.beforeHeight200))],
          afterRasterHeight200: [Math.min(...frames.map(f => f.afterHeight200)), Math.max(...frames.map(f => f.afterHeight200))] });
      }
      await page.evaluate(() => activityComparison.show(['running-first-20261006', 'exercise-repair-20261006', 'charging-cozy-20261007'], 6));
      await page.screenshot({ path: path.join(output, 'three-sources-before-after-200px.png'), fullPage: true });
      await page.evaluate(() => activityComparison.show(['celebrate'], 7));
      await page.screenshot({ path: path.join(output, 'party-long-whistle-before-after.png'), fullPage: true });
      await page.close(); // Release source bitmaps before opening the full product renderer.
      page = await context.newPage();
    });
    await test('real-product-large-small-clock-footer-and-live-timer', async item => {
      const errors = []; page.on('pageerror', e => errors.push(e.message));
      await page.goto(base + 'preview/');
      await page.waitForFunction(() => ['ready','error'].includes(window.__patrickPreviewShell?.report.status));
      assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.status), 'ready');
      await page.locator('#auto-idle').uncheck();
      await page.locator('#face-layout').selectOption('activity');
      await page.locator('[data-experience-tab=timer]').click();
      await page.locator('#activity-kind').selectOption('running'); await page.locator('#activity-minutes').fill('5'); await page.locator('#start-activity').click();
      await page.waitForTimeout(1300);
      await page.locator('#pause-activity').click(); const paused = await page.locator('.enlarged [data-layout-countdown]').textContent();
      await page.waitForTimeout(1100); assert.equal(await page.locator('.enlarged [data-layout-countdown]').textContent(), paused);
      assert.equal(await page.locator('.enlarged [data-layout-state]').textContent(), '已暫停');
      await page.locator('#resume-activity').click();
      await page.waitForFunction(value => document.querySelector('.enlarged [data-layout-countdown]').textContent !== value, paused, { timeout: 4000 });
      assert.notEqual(await page.locator('.enlarged [data-layout-countdown]').textContent(), paused);
      await page.locator('#pause-activity').click();
      await page.reload(); await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready');
      await page.locator('.viewports').screenshot({ path: path.join(output, 'product-current-large-and-200px.png') });
      const stored = await page.evaluate(() => localStorage.getItem('patrick.experience.v1'));
      // Actual product renderer, receiving the old layout and CSS through isolated request fixtures.
      const oldLayouts=read('experience/layouts.json');oldLayouts.layouts=oldLayouts.layouts.map(x=>x.id==='activity'?before:x);
      await page.route('**/experience/layouts.json*',route=>route.fulfill({contentType:'application/json',body:JSON.stringify(oldLayouts)}));
      await page.route('**/preview/styles.css*',route=>route.fulfill({contentType:'text/css',body:fs.readFileSync(path.join(root,'preview/styles.css'),'utf8')+'\n.layout-information{display:flex;flex-direction:column;justify-content:center;align-items:stretch;gap:2.2cqw;border-top:0;border-left:1px solid #85608077;padding-left:3cqw;font-size:5cqw}.layout-information strong{font-size:8.65cqw}.layout-information [data-layout-state]{font-size:4.55cqw}.layout-information [data-layout-care]{display:block}.layout-information progress{margin:0 0 2cqw}'}));
      await page.reload(); await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready');
      await page.locator('.viewports').screenshot({ path: path.join(output, 'product-before-large-and-200px.png') });
      await page.unroute('**/experience/layouts.json*');await page.unroute('**/preview/styles.css*');
      await page.reload(); await page.waitForFunction(() => window.__patrickPreviewShell?.report.status === 'ready');
      assert.equal(await page.locator('#face-layout').inputValue(), 'activity');
      assert.equal(JSON.parse(stored).settings.layoutID, 'activity');
      item.typography=[];
      for (const width of [390,320]) {
        await page.setViewportSize({ width, height: 1000 });
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'no horizontal overflow');
        const result = await page.locator('.wrist .screen').evaluate(screen => {
          const rect = screen.getBoundingClientRect(), panel = screen.querySelector('.layout-information'), p = panel.getBoundingClientRect();
          return { stageWidth:rect.width, clockSize:parseFloat(getComputedStyle(screen.querySelector('[data-clock]')).fontSize), panel:[p.left,p.top,p.right,p.bottom], children:[...panel.children].filter(n=>getComputedStyle(n).display!=='none').map(n=>{const r=n.getBoundingClientRect();return{tag:n.tagName,font:parseFloat(getComputedStyle(n).fontSize),bounds:[r.left,r.top,r.right,r.bottom]};}) };
        });
        assert.equal(Math.round(result.stageWidth),200);assert.ok(result.clockSize>=28);
        for(const c of result.children){assert.ok(c.font>=8);assert.ok(c.bounds[0]>=result.panel[0]-.5&&c.bounds[1]>=result.panel[1]-.5&&c.bounds[2]<=result.panel[2]+.5&&c.bounds[3]<=result.panel[3]+.5,JSON.stringify(c));}
        item.typography.push({width,...result});
        await page.locator('.viewports').screenshot({path:path.join(output,`product-${width}px.png`)});
      }
      assert.deepEqual(errors,[]);
    });
  } finally { await browser.close(); report.finishedAt=new Date().toISOString(); fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n'); }
  if(report.cases.some(c=>!c.passed))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1;});
