// Real assets + isolated storage. Layout coverage, not approval of drawing quality.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..'), output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/20261006-layouts');
const base = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const layouts = JSON.parse(fs.readFileSync(path.join(root, 'experience/layouts.json'))).layouts;
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json')));
const report = { startedAt: new Date().toISOString(), artApproved: false, nativeCompiled: false, cases: [] };
fs.mkdirSync(output, { recursive: true });
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE_PATH });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, timezoneId: 'Asia/Hong_Kong' });
  const page = await context.newPage(), errors = [], httpErrors = [];
  page.on('pageerror', error => errors.push(error.message)); page.on('response', response => { if (response.status() >= 400) httpErrors.push(response.url()); });
  await page.addInitScript(() => {
    window.__layoutSources = new Map();
    const draw = CanvasRenderingContext2D.prototype.drawImage;
    CanvasRenderingContext2D.prototype.drawImage = function (...args) {
      if (this.canvas.dataset.regionClip) {
        const id = this.canvas.dataset.regionClip;
        if (!window.__layoutSources.has(id)) window.__layoutSources.set(id, []);
        window.__layoutSources.get(id)[Number(this.canvas.dataset.sourceFrame)] = this.canvas;
      }
      return draw.apply(this, args);
    };
  });
  await page.clock.install({ time: new Date('2026-10-06T06:01:00Z') });
  await page.clock.pauseAt(new Date('2026-10-06T06:01:01Z'));
  const ready = async (suffix = '') => {
    await page.goto(base + suffix); await page.waitForFunction(() => ['ready','error'].includes(window.__patrickPreviewShell?.report.status));
    const state = await page.evaluate(() => window.__patrickPreviewShell.report); assert.equal(state.status, 'ready', state.lastError); return state;
  };
  async function test(name, fn) {
    const item = { name, passed: false }; report.cases.push(item);
    try { await fn(item); item.passed = true; console.log(`PASS ${name}`); }
    catch (error) { item.error = error.stack; console.error(`FAIL ${name}: ${error.message}`); await page.screenshot({ path: path.join(output, `${name}-failure.png`), fullPage: true }).catch(() => {}); }
  }
  try {
    await test('four-layouts-real-core-time-safety-small-size-and-storage', async item => {
      await ready(); assert.equal(await page.locator('#face-layout').inputValue(), 'classic');
      await page.locator('#auto-idle').uncheck();
      await page.locator('.experience-settings summary').click(); await page.locator('#ambience-enabled').uncheck();
      await page.locator('#toggle-review').click(); await page.locator('#clip-select').selectOption('yawn');
      item.frames = await page.evaluate(({ catalog, layouts }) => {
        const result = [], rendering = window.__patrickPreviewShell.report.rendering;
        for (const clip of catalog.clips.filter(value => value.atlas && value.frameRegions)) {
          const sourceFrames = window.__layoutSources.get(clip.id), canvas = rendering[clip.id].canvas;
          const scale = clip.scale || 1, width = 665.6 * scale, height = width;
          const target = catalog.master.anchorNormalized, anchor = canvas.anchorNormalized;
          const rect = [83.2 + 665.6 * target[0] - width * anchor[0], 248 + 665.6 * target[1] - height * anchor[1], width, height];
          const indices = clip.frameIndices || Array.from({ length: clip.frameCount }, (_, i) => i);
          for (const sourceIndex of [...new Set(indices)]) {
            const source = sourceFrames[sourceIndex], pixels = source.getContext('2d').getImageData(0,0,source.width,source.height).data;
            let x0=source.width,y0=source.height,x1=-1,y1=-1,count=0;
            for (let y=0;y<source.height;y++) for(let x=0;x<source.width;x++) if(pixels[4*(y*source.width+x)+3]>=128){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);count++;}
            for (const layout of layouts) {
              const [s,tx,ty]=layout.characterTransform;
              const bounds=[(rect[0]+x0/source.width*width)*s+tx,(rect[1]+y0/source.height*height)*s+ty,
                (rect[0]+(x1+1)/source.width*width)*s+tx,(rect[1]+(y1+1)/source.height*height)*s+ty];
              result.push({clip:clip.id,frame:sourceIndex,layout:layout.id,bounds,count,scale:width/source.width*s});
            }
          }
        }
        return result;
      }, { catalog, layouts });
      item.typography = [];
      for (const layout of layouts) {
        await page.locator('#face-layout').selectOption(layout.id);
        for (const timeFormat of ['24', '12']) {
          await page.locator('#time-format').selectOption(timeFormat);
          const zones = await page.locator('.enlarged .screen').evaluate(screen => {
            const stage = screen.getBoundingClientRect();
            return [...screen.querySelectorAll('[data-clock],[data-watch-date],.layout-information:not([hidden])')].map(node => {
              const rect=node.getBoundingClientRect();return {kind:node.className,bounds:[(rect.left-stage.left)/stage.width*832,(rect.top-stage.top)/stage.height*992,(rect.right-stage.left)/stage.width*832,(rect.bottom-stage.top)/stage.height*992]};
            });
          });
          item.typography.push({ layout: layout.id, timeFormat, zones });
          for (const entry of item.frames.filter(value => value.layout === layout.id)) {
            assert.ok(entry.count > 1000, `${entry.clip} has visible pixels`);
            const b=entry.bounds;assert.ok(b[0]>=0&&b[1]>=0&&b[2]<=832&&b[3]<=992, `${JSON.stringify(entry)} outside stage`);
            for(const zone of zones){const z=zone.bounds;assert.ok(b[2]<=z[0]||b[0]>=z[2]||b[3]<=z[1]||b[1]>=z[3],`${entry.clip} frame ${entry.frame+1} ${layout.id} overlaps ${zone.kind}: ${JSON.stringify({b,z})}`);}
          }
        }
        await page.locator('#time-format').selectOption('24');
        await page.locator('.viewports').screenshot({path:path.join(output,`${layout.id}-large-and-200px.png`)});
        for (const width of [390,320]) {
          await page.setViewportSize({width,height:900});
          assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'no horizontal overflow');
          const sizes=await page.locator('[data-clock]').evaluateAll(nodes=>nodes.map(node=>{const r=node.getBoundingClientRect();return{width:r.width,height:r.height,screen:node.closest('.screen').getBoundingClientRect().width};}));
          assert.ok(sizes.every(size=>size.width<size.screen && size.height>20),'time remains readable in both views');
          if(width===320)await page.locator('.viewports').screenshot({path:path.join(output,`${layout.id}-small-phone.png`)});
        }
        await page.setViewportSize({width:1440,height:1100});
      }
      const review = '{"note":"keep previous feedback","version":2}';
      await page.evaluate(value=>localStorage.setItem('patrick.animation-review.patrick-bedtime-yawn-v1.v2',value),review);
      await ready();assert.equal(await page.locator('#face-layout').inputValue(),'activity');
      assert.equal(await page.evaluate(()=>localStorage.getItem('patrick.animation-review.patrick-bedtime-yawn-v1.v2')),review);
    });
    await test('activity-face-live-countdown-pause-resume-and-arms', async item => {
      await page.locator('[data-experience-tab=timer]').click();await page.locator('#activity-kind').selectOption('running');await page.locator('#activity-minutes').fill('1');await page.locator('#start-activity').click();
      await page.clock.runFor(3000);assert.match(await page.locator('.enlarged [data-layout-title]').textContent(),/跑步/);
      await page.locator('#pause-activity').click();const paused=await page.locator('.enlarged [data-layout-countdown]').textContent();
      await page.clock.runFor(10000);assert.equal(await page.locator('.enlarged [data-layout-countdown]').textContent(),paused);assert.equal(await page.locator('.enlarged [data-layout-state]').textContent(),'已暫停');
      await page.locator('#resume-activity').click();await page.clock.runFor(2000);assert.notEqual(await page.locator('.enlarged [data-layout-countdown]').textContent(),paused);
      await page.locator('.viewports').screenshot({path:path.join(output,'activity-running-countdown.png')});
      await page.locator('#stop-timer').click();if(await page.locator('#pause').isEnabled())await page.locator('#pause').click();
      await page.locator('.experience-settings summary').click();await page.locator('#clock-mode').selectOption('arms');
      await page.waitForFunction(()=>window.__patrickPreviewShell.report.clockArtLoaded);await page.clock.runFor(100);
      item.arms=[];
      for(const layout of layouts){await page.locator('#face-layout').selectOption(layout.id);await page.clock.runFor(50);const state=await page.evaluate(()=>window.__patrickPreviewShell.report);assert.equal(state.armClockActive,true);item.arms.push({layout:layout.id,angles:state.armAngles});await page.locator('.enlarged .screen').screenshot({path:path.join(output,`${layout.id}-arms.png`)});}
    });
    await test('candidate-review-keeps-classic-geometry-and-main-storage',async item=>{
      const before=await page.evaluate(()=>Object.fromEntries(Object.entries(localStorage).filter(([key])=>!key.startsWith('patrick.animation-candidate-review.'))));
      await ready('?review=candidates');assert.equal(await page.locator('#layout-picker').isVisible(),false);assert.equal(await page.locator('.screen[data-layout]').count(),0);
      await page.locator('#next-frame').click();await page.clock.runFor(25000);assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false);
      const after=await page.evaluate(()=>Object.fromEntries(Object.entries(localStorage).filter(([key])=>!key.startsWith('patrick.animation-candidate-review.'))));assert.deepEqual(after,before);item.preservedKeys=Object.keys(after);
    });
    assert.deepEqual(errors,[]);assert.deepEqual(httpErrors,[]);
  } finally {report.pageErrors=errors;report.httpErrors=httpErrors;report.finishedAt=new Date().toISOString();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));await browser.close();}
  if(report.cases.some(item=>!item.passed))process.exitCode=1;
})().catch(error=>{console.error(error);process.exitCode=1;});
