// Disposable browser contexts only. Synthetic scheduler fixtures test logic,
// never claim that their reused source drawings are finished blink/interaction art.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/multi-clips');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json'), 'utf8'));
const liveClips = catalog.clips.filter(clip => clip.atlas);
const seed = liveClips.find(clip => clip.id === 'yawn') || liveClips[0];
if (!seed) throw new Error('No actual atlas is available for browser QA.');
const report = { startedAt: new Date().toISOString(), url: address, actualCatalogClips: liveClips.map(clip => ({ id: clip.id, version: clip.version, sha256: clip.sha256 })), cases: [] };
const caseFilter = process.env.QA_CASE_FILTER ? new RegExp(process.env.QA_CASE_FILTER) : null;
if (caseFilter) report.caseFilter = process.env.QA_CASE_FILTER;
fs.mkdirSync(output, { recursive: true });
async function waitState(page, expected) {
 const deadline = Date.now() + 25000;
 while (Date.now() < deadline) {
  const status = await page.evaluate(() => window.__patrickPreviewShell?.report.status);
  if (status === expected) return;
  if (status === 'error' && expected !== 'error') throw new Error(await page.locator('#recovery-message').textContent());
  await new Promise(resolve => setTimeout(resolve, 40));
 }
 throw new Error(`Preview did not reach ${expected}`);
}
async function ready(page) {
 await page.goto(address, { waitUntil: 'domcontentloaded' });
 await waitState(page, 'ready');
 assert.equal(await page.evaluate(() => window.__patrickPreviewShell.report.status), 'ready', await page.locator('#status').textContent());
}
async function inspectFrame(page) {
 return page.evaluate(() => {
  const a = document.querySelector('#face'), b = document.querySelector('#wrist-face');
  const pixels = a.getContext('2d').getImageData(0,0,a.width,a.height).data;
  const second = b.getContext('2d').getImageData(0,0,b.width,b.height).data;
  let count=0,minY=a.height,maxY=-1,same=pixels.length===second.length;
  for(let i=0;i<pixels.length;i+=4){ if(pixels[i+3]>=128){count++;const y=Math.floor(i/4/a.width);minY=Math.min(minY,y);maxY=Math.max(maxY,y);} if(same&&(pixels[i]!==second[i]||pixels[i+1]!==second[i+1]||pixels[i+2]!==second[i+2]||pixels[i+3]!==second[i+3]))same=false; }
  const large=a.getBoundingClientRect(),small=b.getBoundingClientRect(),time=document.querySelector('#digital-time').getBoundingClientRect();
  return {count,minY,maxY,same,width:a.width,height:a.height,frame:a.dataset.frame,wristFrame:b.dataset.frame,clip:a.dataset.clip,wristClip:b.dataset.clip,smallWidth:small.width,ratio:large.width/large.height,clockBottom:time.bottom,artTop:large.top+minY/a.height*large.height,pageWidth:document.documentElement.scrollWidth,viewport:innerWidth,draws:window.__draws.slice(-2)};
 });
}
function fixtureCatalog() {
 const scenes=['sleeping','awake','charging','focus','exercise','bath','celebrate'];
 const variant=(id,extra={})=>({...seed,id,title:`TEST FIXTURE ${id}`,frameCount:8,frameIndices:[0,1,2,3,4,5,6,7],durationsMs:Array(8).fill(70),scenes,triggerKinds:['manual'],...extra});
 return {...catalog,clips:[seed,...['normal','slow','double'].map((kind,i)=>variant(`idle-blink-${kind}`,{idleVariant:kind,category:'idle',triggerKinds:['idle'],...(i===2?{frameCount:16,frameIndices:[0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,7],durationsMs:Array(16).fill(60)}:{})})),...['pet','feed','focus','celebrate','charging','exercise'].map(id=>variant(id)),{id:'bath',title:'洗澡待補',scenes:['bath'],status:'planned'}]};
}
(async()=>{
 const launch={headless:true}; if(process.env.CHROMIUM_EXECUTABLE_PATH)launch.executablePath=process.env.CHROMIUM_EXECUTABLE_PATH;
 const browser=await chromium.launch(launch);
 async function test(name, options, body){
  if (caseFilter && !caseFilter.test(name)) return;
  const result={name,passed:false}; const context=await browser.newContext({viewport:{width:1440,height:1100},timezoneId:'Asia/Hong_Kong',acceptDownloads:true,...options});
  const page=await context.newPage(); const errors=[];page.on('pageerror',error=>errors.push(error.message));page.setDefaultTimeout(10000);
  try{
   await page.addInitScript(()=>{
    const original=CanvasRenderingContext2D.prototype.drawImage; window.__draws=[];
    CanvasRenderingContext2D.prototype.drawImage=function(...args){if(['face','wrist-face'].includes(this.canvas.id)){window.__draws.push({canvas:this.canvas.id,args:args.slice(1)});if(window.__draws.length>100)window.__draws.shift();}return original.apply(this,args);};
   });
   await page.clock.install({time:new Date('2026-09-27T06:00:00Z')}); await page.clock.pauseAt(new Date('2026-09-27T06:01:00Z'));
   await body(page,result,context); assert.deepEqual(errors,[]);result.passed=true;console.log(`PASS ${name}`);
  }catch(error){result.error=error.stack;result.pageErrors=errors;console.error(`FAIL ${name}: ${error.message}`);await page.screenshot({path:path.join(output,`${name}-failure.png`),fullPage:true,timeout:3000}).catch(()=>{});}
  finally{report.cases.push(result);await context.close();}
 }
 try{
  await test('actual-art-fixed-frames-and-two-sizes',{},async(page,result)=>{
   await ready(page); result.clips=[];
   for(const clip of liveClips){
    await page.locator('#clip-select').selectOption(clip.id);
    assert.equal(await page.locator('#frames .frame').count(),clip.frameCount);
    let destination=null;const samples=[];
    for(const frame of [...new Set([0,Math.floor(clip.frameCount/2),clip.frameCount-1])]){
     await page.locator('#frames .frame').nth(frame).click(); const observed=await inspectFrame(page);
     assert.equal(observed.frame,String(frame));assert.equal(observed.wristFrame,String(frame));assert.equal(observed.clip,clip.id);assert.equal(observed.wristClip,clip.id);
     assert.equal(observed.same,true,'both sizes must use identical backing pixels');assert.ok(observed.count>1000,'actual character pixels must exist');
     assert.equal(observed.width,832);assert.equal(observed.height,992);assert.ok(Math.abs(observed.smallWidth-200)<.1);assert.ok(Math.abs(observed.ratio-416/496)<.001);
     assert.ok(observed.minY>=Math.floor(992*.24),'visible character must stay below time-safe zone');assert.ok(observed.maxY<=Math.ceil(992*.93),'visible character must stay above bottom-safe line');assert.ok(observed.clockBottom<observed.artTop);
     const draw=observed.draws.find(item=>item.canvas==='face').args;
     const index=clip.frameIndices?.[frame]??frame; const sw=clip.width/clip.columns,sh=clip.height/clip.rows;
     const region = clip.frameRegions ? JSON.parse(fs.readFileSync(path.join(root,clip.frameRegions.path),'utf8')) : null;
     assert.deepEqual(draw.slice(0,4),region ? [0,0,region.canvas.width,region.canvas.height] : [(index%clip.columns)*sw,Math.floor(index/clip.columns)*sh,sw,sh]);
     if(destination)assert.deepEqual(draw.slice(4),destination,'per-frame destinations must never refit bounds');else destination=draw.slice(4);
     samples.push({frame,paintedPixels:observed.count,minY:observed.minY,maxY:observed.maxY,destination});
    }
    result.clips.push({id:clip.id,samples});
   }
   await page.locator('#clip-select').selectOption(seed.id);await page.locator('#play').click();
   await page.clock.runFor(seed.durationsMs.reduce((a,b)=>a+b,0)+100);
   assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false,'actual clip must end after one performance');
   assert.equal(await page.locator('#face').getAttribute('data-frame'),String(seed.frameCount-1));
   await page.clock.runFor(12000);assert.equal(await page.locator('#face').getAttribute('data-frame'),String(seed.frameCount-1),'a manual review never loops');
   await page.locator('#frames .frame').nth(0).click();
   await page.screenshot({path:path.join(output,'desktop.png'),fullPage:true});
   const before=await page.locator('#digital-time').getAttribute('datetime');await page.clock.runFor(61000);const after=await page.locator('#digital-time').getAttribute('datetime');
   assert.ok(Date.parse(after)-Date.parse(before)>=60000);assert.equal(await page.locator('#face').getAttribute('data-frame'),'0');
   assert.equal(await page.locator('[data-clock]').nth(0).textContent(),await page.locator('[data-clock]').nth(1).textContent());
  });
  for(const width of [375,390,430])await test(`responsive-${width}`,{viewport:{width,height:900}},async page=>{
   await ready(page);const view=await inspectFrame(page);assert.ok(view.pageWidth<=width);assert.ok(Math.abs(view.smallWidth-200)<.1);
   await page.screenshot({path:path.join(output,`mobile-${width}.png`),fullPage:true});
  });
  await test('scheduler-fixture-priority-quiet-and-no-catchup',{},async(page,result)=>{
   result.fixture='Actual seed atlas reused only to exercise playback timing; not validation of missing art.';
   await page.route('**/animation/catalog.json*',route=>route.fulfill({json:fixtureCatalog()}));await page.addInitScript(()=>{Math.random=()=>0;});await ready(page);
   const read=()=>page.evaluate(()=>window.__patrickPreviewShell.report);
   await page.clock.runFor(9900);assert.equal((await read()).currentClip,seed.id);
   await page.clock.runFor(900);assert.equal((await read()).idleLastId,'idle-blink-normal');
   await page.clock.runFor(11200);assert.equal((await read()).idleLastId,'idle-blink-slow');
   await page.locator('#frames .frame').nth(2).click();const inspected=await page.locator('#face').getAttribute('data-clip');await page.clock.runFor(60000);
   assert.equal((await read()).reviewing,true);assert.equal(await page.locator('#face').getAttribute('data-clip'),inspected);assert.equal(await page.locator('#face').getAttribute('data-frame'),'2');
   await page.locator('#resume-idle').click();const last=(await read()).idleLastId;await page.clock.runFor(9900);assert.equal((await read()).idleLastId,last);
   await page.clock.runFor(1500);assert.notEqual((await read()).idleLastId,last);
   await page.locator('#pet').click();assert.equal((await read()).currentClip,'pet');assert.equal((await read()).playKind,'interaction');await page.clock.runFor(1000);assert.equal((await read()).playing,false);
   await page.locator('.settings summary').click();await page.locator('#wrist-down').check();const stopped=(await read()).currentClip;await page.clock.runFor(45000);assert.equal((await read()).currentClip,stopped);
   await page.locator('#wrist-down').uncheck();await page.clock.runFor(9900);assert.equal((await read()).currentClip,stopped);
   await page.emulateMedia({reducedMotion:'reduce'});await page.clock.runFor(30000);assert.equal((await read()).playing,false);await page.locator('#play').click();assert.equal((await read()).reviewing,true);assert.equal((await read()).playing,false);
   await page.emulateMedia({reducedMotion:'no-preference'});await page.locator('#resume-idle').click();
   await page.evaluate(()=>{window.__hidden=true;Object.defineProperty(document,'hidden',{configurable:true,get:()=>window.__hidden});document.dispatchEvent(new Event('visibilitychange'));});
   const hiddenClip=(await read()).currentClip;await page.clock.runFor(60000);assert.equal((await read()).currentClip,hiddenClip);
   await page.evaluate(()=>{window.__hidden=false;document.dispatchEvent(new Event('visibilitychange'));});await page.clock.runFor(9900);assert.equal((await read()).currentClip,hiddenClip);
   await page.locator('#auto-idle').uncheck();await page.clock.runFor(60000);assert.equal((await read()).playing,false);
   await page.locator('#scene').selectOption('bath');assert.equal(await page.locator('#frames .frame').count(),0);assert.match(await page.locator('#status').textContent(),/待補/);
   assert.equal((await inspectFrame(page)).count,0,'missing scene must clear old artwork');
  });
  await test('bedtime-once-persistence-and-review-categories',{},async(page,result)=>{
   await page.route('**/animation/catalog.json*',route=>route.fulfill({json:fixtureCatalog()}));await ready(page);
   await page.evaluate(()=>localStorage.setItem('qa.keep-old-review','keep me'));
   await page.locator('#scene').selectOption('awake');await page.locator('#scene').selectOption('sleeping');
   assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playKind),'scene');await page.clock.runFor(seed.durationsMs.reduce((a,b)=>a+b,0)+100);
   const first=await page.evaluate(()=>JSON.parse(localStorage.getItem('patrick.animation-events.v1')).bedtimeLastAt);
   await page.locator('#scene').selectOption('awake');await page.locator('#scene').selectOption('sleeping');assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false);assert.match(await page.locator('#scene-explanation').textContent(),/冷卻/);
   await page.reload();await waitState(page,'ready');assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('patrick.animation-events.v1')).bedtimeLastAt),first);
   await page.locator('#clip-select').selectOption(seed.id);await page.locator('#frames .frame').nth(3).click();await page.locator('#verdict').selectOption('liked');await page.locator('#review-note').fill('動作意見：眼睛有變化');
   await page.locator('[data-review-scope=outfit]').click();await page.locator('#verdict').selectOption('revise');await page.locator('#review-note').fill('造型意見：帽子要穩定');
   const downloadPromise=page.waitForEvent('download');await page.locator('#export-review').click();const download=await downloadPromise;const target=path.join(output,'review-export.json');await download.saveAs(target);
   const exported=JSON.parse(fs.readFileSync(target,'utf8'));const review=exported.clips.find(clip=>clip.asset===seed.id);
   assert.equal(exported.schemaVersion,2);assert.equal(review.sha256,seed.sha256);assert.equal(review.version,seed.version);assert.equal(review.sections.action.frames[3],'liked');assert.equal(review.sections.outfit.frames[3],'revise');assert.match(review.sections.action.note,/動作意見/);assert.match(review.sections.outfit.note,/造型意見/);
   await page.reload();await waitState(page,'ready');await page.locator('#clip-select').selectOption(seed.id);assert.match(await page.locator('#review-note').inputValue(),/動作意見/);assert.equal(await page.evaluate(()=>localStorage.getItem('qa.keep-old-review')),'keep me');
   await page.locator('.settings summary').click();await page.locator('#focus-timer').click();await page.locator('#scene-date').fill('2027-02-06');await page.locator('#scene-date').dispatchEvent('change');await page.clock.runFor(1000);assert.match(await page.locator('#timer-status').textContent(),/24:59/);assert.match(await page.locator('#date-status').textContent(),/新年|初一|農曆/);
   result.reviewSHA=review.sha256;
  });
  await test('legacy-yawn-v2-review-is-preserved',{},async(page,result)=>{
   assert.equal(seed.id,'yawn');assert.equal(seed.version,2,'legacy migration case targets approved yawn v2');
   const legacyKey='patrick.animation-review.patrick-bedtime-yawn-v1.v2';
   const original=JSON.stringify({asset:'patrick-bedtime-yawn-v1',version:2,sha256:seed.sha256,frames:{2:'liked',5:'revise'},note:'舊版哈欠意見：保留這一句。',updatedAt:'2026-09-26T12:00:00Z'});
   await page.addInitScript(({key,value})=>{if(localStorage.getItem(key)===null)localStorage.setItem(key,value);},{key:legacyKey,value:original});
   await ready(page);await page.locator('#clip-select').selectOption('yawn');assert.match(await page.locator('#review-note').inputValue(),/舊版哈欠意見/);
   await page.locator('#frames .frame').nth(2).click();assert.equal(await page.locator('#verdict').inputValue(),'liked');
   await page.locator('#review-note').fill('沿用舊意見後，新版本繼續補充。');
   const downloadPromise=page.waitForEvent('download');await page.locator('#export-review').click();const download=await downloadPromise;const target=path.join(output,'legacy-review-export.json');await download.saveAs(target);
   const migrated=JSON.parse(fs.readFileSync(target,'utf8')).clips.find(clip=>clip.asset==='yawn');assert.equal(migrated.sections.action.frames[2],'liked');assert.equal(migrated.sections.action.frames[5],'revise');assert.match(migrated.sections.action.note,/繼續補充/);
   assert.equal(await page.evaluate(key=>localStorage.getItem(key),legacyKey),original,'original old storage must remain byte-for-byte unchanged');
   await page.reload();await waitState(page,'ready');assert.match(await page.locator('#review-note').inputValue(),/繼續補充/);assert.equal(await page.evaluate(key=>localStorage.getItem(key),legacyKey),original);
   result.legacyKey=legacyKey;result.sha256=seed.sha256;
  });
  await test('partial-404-exports-existing-review',{},async page=>{
   const fixture=fixtureCatalog();const missing=fixture.clips.find(clip=>clip.id==='pet');missing.atlas='animation/__qa-missing.png';
   await page.route('**/animation/catalog.json*',route=>route.fulfill({json:fixture}));
   await page.route('**/animation/__qa-missing.png*',route=>route.fulfill({status:404,body:'not found'}));
   await page.addInitScript(({version,sha256})=>localStorage.setItem(`patrick.animation-review.pet.v${version}.${sha256}`,JSON.stringify({asset:'pet',version,sha256,frames:{0:'liked'},note:'先前已寫的意見'})),{version:missing.version,sha256:missing.sha256});
   await ready(page);assert.equal(await page.locator('#preview-recovery').isVisible(),true);
   const downloadPromise=page.waitForEvent('download');await page.locator('#export-review').click();const download=await downloadPromise;const target=path.join(output,'partial-review-export.json');await download.saveAs(target);
   const review=JSON.parse(fs.readFileSync(target,'utf8')).clips.find(clip=>clip.asset==='pet');
   assert.equal(review.imageAvailable,false);assert.equal(review.sections.action.frames[0],'liked');assert.match(review.sections.action.note,/先前/);
  });
  await test('missing-images-clock-and-retry-preserve-storage',{},async page=>{
   await page.addInitScript(()=>localStorage.setItem('qa.keep-old-review','keep me'));
   await page.route('**/animation/**/*.png*',route=>route.fulfill({status:404,body:'not found'}));
   await page.goto(address);await waitState(page,'error');assert.equal(await page.locator('#preview-recovery').isVisible(),true);
   const before=await page.locator('#digital-time').getAttribute('datetime');await page.clock.runFor(61000);assert.ok(Date.parse(await page.locator('#digital-time').getAttribute('datetime'))-Date.parse(before)>=60000);
   await page.unroute('**/animation/**/*.png*');await page.locator('#retry-preview').click();await waitState(page,'ready');assert.equal(await page.evaluate(()=>localStorage.getItem('qa.keep-old-review')),'keep me');assert.ok((await inspectFrame(page)).count>1000);
  });
 }finally{await browser.close();report.finishedAt=new Date().toISOString();report.passed=report.cases.every(item=>item.passed);fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));}
 if(!report.passed)process.exitCode=1;
})();
