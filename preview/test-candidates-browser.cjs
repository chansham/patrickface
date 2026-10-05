// Candidate-mode browser checks verify review UI and isolation, never art quality.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/candidate-review');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/preview/';
const catalog = JSON.parse(fs.readFileSync(path.join(root,'animation/candidates.json'),'utf8'));
assert.ok(catalog.clips.length > 0, 'candidate catalog must contain real review artwork');
const report={startedAt:new Date().toISOString(),url:`${address}?review=candidates`,artQualityApproved:false,scope:'UI, manual playback, fixed layout and storage isolation. Known artwork defects remain.',catalogClipCount:catalog.clips.length,catalogFrameCount:catalog.clips.reduce((sum,clip)=>sum+clip.frameCount,0),cases:[]};
fs.mkdirSync(output,{recursive:true});
const protectedValues={
 'patrick.animation-player.v1':JSON.stringify({version:1,scene:'awake',enabled:true}),
 'patrick.animation-events.v1':JSON.stringify({version:1,bedtimeLastAt:123,timerHandledAt:456}),
 'patrick.pet.v1':JSON.stringify({version:1,mode:'auto',activity:{mode:'focus',startedAt:1,endsAt:1000},fed:12,mood:'calm'}),
 'patrick.experience.v1':JSON.stringify({version:1,outfitId:'keep-this-outfit',settings:{sound:true,timeFormat:'12'},journal:[{id:'keep',at:1,type:'pet',text:'保留原日記'}]})
};
async function ready(page,url=report.url){
 await page.goto(url,{waitUntil:'domcontentloaded'});const deadline=Date.now()+25000;
 while(Date.now()<deadline){const state=await page.evaluate(()=>window.__patrickPreviewShell?.report);if(state?.status==='ready')return state;if(state?.status==='error')throw new Error(state.lastError);await new Promise(resolve=>setTimeout(resolve,40));}
 throw new Error('Review page did not become ready');
}
async function sameFrame(page){return page.evaluate(()=>{
 const a=document.querySelector('#face'),b=document.querySelector('#wrist-face');const x=a.getContext('2d').getImageData(0,0,a.width,a.height).data,y=b.getContext('2d').getImageData(0,0,b.width,b.height).data;
 let same=true,painted=0,minY=a.height,maxY=-1;for(let i=0;i<x.length;i+=4){if(x[i+3]>=128){painted++;const row=Math.floor(i/4/a.width);minY=Math.min(minY,row);maxY=Math.max(maxY,row);}if(same&&(x[i]!==y[i]||x[i+1]!==y[i+1]||x[i+2]!==y[i+2]||x[i+3]!==y[i+3]))same=false;}
 return{same,painted,minY,maxY,frame:a.dataset.frame,smallFrame:b.dataset.frame,width:b.getBoundingClientRect().width,clip:a.dataset.clip,draws:window.__draws.slice(-2)};
});}
(async()=>{
 const launch={headless:true};if(process.env.CHROMIUM_EXECUTABLE_PATH)launch.executablePath=process.env.CHROMIUM_EXECUTABLE_PATH;const browser=await chromium.launch(launch);
 async function test(name,options,body){if(process.env.QA_CASE_FILTER&&!new RegExp(process.env.QA_CASE_FILTER).test(name))return;const result={name,passed:false};const context=await browser.newContext({viewport:{width:1440,height:1100},timezoneId:'Asia/Hong_Kong',acceptDownloads:true,...options});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  try{
   await page.addInitScript(values=>{
    for(const[key,value]of Object.entries(values))if(localStorage.getItem(key)===null)localStorage.setItem(key,value);
    window.__writes=[];const set=Storage.prototype.setItem;Storage.prototype.setItem=function(key,value){window.__writes.push(key);return set.call(this,key,value);};
    window.__draws=[];const draw=CanvasRenderingContext2D.prototype.drawImage;CanvasRenderingContext2D.prototype.drawImage=function(...args){if(['face','wrist-face'].includes(this.canvas.id)){window.__draws.push({canvas:this.canvas.id,args:args.slice(1)});if(window.__draws.length>20)window.__draws.shift();}return draw.apply(this,args);};
   },protectedValues);
   await page.clock.install({time:new Date('2026-09-27T06:00:00Z')});await page.clock.pauseAt(new Date('2026-09-27T06:01:00Z'));
   await body(page,result);assert.deepEqual(errors,[]);result.passed=true;console.log(`PASS ${name}`);
  }catch(error){result.error=error.stack;result.pageErrors=errors;console.error(`FAIL ${name}: ${error.message}`);await page.screenshot({path:path.join(output,`${name}-failure.png`),fullPage:true,timeout:3000}).catch(()=>{});}
  finally{report.cases.push(result);await context.close();}
 }
 try{
  await test('all-real-candidates-manual-only-and-fixed-two-sizes',{},async(page,result)=>{
   const initial=await ready(page);assert.equal(initial.mode,'candidates');assert.equal(initial.catalog,'animation/candidates.json');assert.equal(initial.clipsLoaded.length,catalog.clips.length);assert.match(await page.locator('#candidate-banner').textContent(),/待修動畫審稿｜非正式播放素材/);
   for(const selector of ['.scene-picker','.interactions','.idle-control','.settings'])assert.equal(await page.locator(selector).isVisible(),false);
   const before=await sameFrame(page);await page.clock.runFor(120000);assert.equal((await sameFrame(page)).frame,before.frame);assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false);
   assert.deepEqual(await page.evaluate(()=>window.__writes),[],'candidate startup and waiting must not write storage');
   result.clips=[];
   for(const clip of catalog.clips){
    await page.locator('#clip-select').selectOption(clip.id);assert.equal(await page.locator('#frames .frame').count(),clip.frameCount);assert.match(await page.locator('#clip-description').textContent(),/已知問題/);assert.ok((await page.locator('#clip-description').textContent()).includes(clip.description));
    let destination;const observations=[];
    for(let frame=0;frame<clip.frameCount;frame++){
     await page.locator('#frames .frame').nth(frame).click();const seen=await sameFrame(page);assert.equal(seen.same,true);assert.equal(seen.frame,String(frame));assert.equal(seen.smallFrame,String(frame));assert.ok(Math.abs(seen.width-200)<.1);assert.ok(seen.painted>1000);
     const rect=seen.draws.find(d=>d.canvas==='face').args;const cell=clip.frameIndices?.[frame]??frame,sw=clip.width/clip.columns,sh=clip.height/clip.rows;const region=clip.frameRegions?JSON.parse(fs.readFileSync(path.join(root,clip.frameRegions.path),'utf8')):null;assert.deepEqual(rect.slice(0,4),region?[0,0,region.canvas.width,region.canvas.height]:[(cell%clip.columns)*sw,Math.floor(cell/clip.columns)*sh,sw,sh]);if(destination)assert.deepEqual(rect.slice(4),destination);else destination=rect.slice(4);
     observations.push({frame,paintedPixels:seen.painted,minY:seen.minY,maxY:seen.maxY,insideNominalSafeBand:seen.minY>=Math.floor(992*.24)&&seen.maxY<=Math.ceil(992*.93)});
     if(clip.id==='celebrate-candidate'&&[0,8,15].includes(frame))await page.locator('.enlarged .screen').screenshot({path:path.join(output,`celebrate-frame-${frame+1}.png`)});
    }
    await page.locator('#play').click();assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playKind),'review');await page.clock.runFor(clip.durationsMs.reduce((a,b)=>a+b,0)+100);assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false);assert.equal(await page.locator('#face').getAttribute('data-frame'),String(clip.frameCount-1));
    await page.clock.runFor(23000);assert.equal(await page.locator('#face').getAttribute('data-frame'),String(clip.frameCount-1));
    await page.locator('#frames .frame').nth(Math.floor(clip.frameCount/2)).click();await page.screenshot({path:path.join(output,`${clip.id}.png`),fullPage:true});
    result.clips.push({id:clip.id,sha256:clip.sha256,qualityStatus:clip.status,destination,frameObservations:observations,qualityApproved:false});
   }
   await page.evaluate(()=>{for(const id of ['scene','auto-idle'])document.querySelector(`#${id}`).dispatchEvent(new Event('change'));for(const id of ['pet','feed','focus-timer','stop-timer','resume-idle'])document.querySelector(`#${id}`).dispatchEvent(new Event('click'));});
   assert.deepEqual(await page.evaluate(()=>window.__writes),[],'even dormant event listeners cannot write companion state');assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false);
   for(const[key,value]of Object.entries(protectedValues))assert.equal(await page.evaluate(k=>localStorage.getItem(k),key),value);
  });
  await test('candidate-review-hash-namespace-and-export',{},async(page,result)=>{
   const clip=process.env.QA_TARGET_CLIP?catalog.clips.find(clip=>clip.id===process.env.QA_TARGET_CLIP):catalog.clips[0];assert.ok(clip,'requested candidate must exist');const mainKey=`patrick.animation-review.${clip.id}.v${clip.version}.${clip.sha256}`;const candidateKey=`patrick.animation-candidate-review.${clip.id}.v${clip.version}.${clip.sha256}`;
   const existing=JSON.stringify({asset:clip.id,version:clip.version,sha256:clip.sha256,frames:{2:'liked'},note:'main namespace must remain separate'});
   await page.addInitScript(({key,value})=>{if(localStorage.getItem(key)===null)localStorage.setItem(key,value);},{key:mainKey,value:existing});
   await ready(page);await page.locator('#clip-select').selectOption(clip.id);assert.equal(await page.locator('#review-note').inputValue(),'');
   await page.locator('#frames .frame').nth(2).click();await page.locator('#verdict').selectOption('revise');await page.locator('#review-note').fill('候選動作：身形跳動要修');await page.locator('[data-review-scope=outfit]').click();await page.locator('#review-note').fill('候選造型：彩邊要修');
   const downloadPromise=page.waitForEvent('download');await page.locator('#export-review').click();const download=await downloadPromise;const target=path.join(output,'candidate-review-export.json');await download.saveAs(target);
   const exported=JSON.parse(fs.readFileSync(target,'utf8'));assert.equal(exported.reviewMode,'candidates');assert.equal(exported.catalog,'animation/candidates.json');assert.equal(exported.clips.length,catalog.clips.length);const saved=exported.clips.find(item=>item.asset===clip.id);assert.equal(saved.sha256,clip.sha256);assert.equal(saved.qualityStatus,clip.status);assert.equal(saved.sections.action.frames[2],'revise');assert.match(saved.sections.action.note,/身形/);assert.match(saved.sections.outfit.note,/彩邊/);assert.equal(await page.evaluate(key=>localStorage.getItem(key),mainKey),existing);
   assert.ok(await page.evaluate(key=>localStorage.getItem(key),candidateKey));for(const[key,value]of Object.entries(protectedValues))assert.equal(await page.evaluate(k=>localStorage.getItem(k),key),value);
   await ready(page);await page.locator('#clip-select').selectOption(clip.id);assert.match(await page.locator('#review-note').inputValue(),/身形/);await page.locator('[data-review-scope=outfit]').click();assert.match(await page.locator('#review-note').inputValue(),/彩邊/);assert.equal(await page.evaluate(key=>localStorage.getItem(key),mainKey),existing);result.candidateStorageKey=candidateKey;
  });
  await test('candidate-filters-preserve-current-frame-and-all-reviews',{},async(page,result)=>{
   await ready(page);assert.equal(await page.locator('#candidate-filters').isVisible(),true);
   const batches=[...new Set(catalog.clips.map(clip=>clip.batch).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'en',{numeric:true}));const latest=batches.at(-1);
   const group=clip=>['idle','interaction','scene'].includes(clip.reviewGroup)?clip.reviewGroup:(clip.idleVariant||clip.category==='idle'||clip.category==='待機'||clip.triggerKinds?.includes('idle'))?'idle':(['interaction','互動'].includes(clip.category)||clip.triggerKinds?.includes('interaction'))?'interaction':'scene';
   const first=catalog.clips[0];await page.locator('#clip-select').selectOption(first.id);const frame=Math.min(2,first.frameCount-1);await page.locator('#frames .frame').nth(frame).click();await page.locator('#review-note').fill('篩選前的動作意見要保留');
   await page.locator('[data-candidate-filter=all]').click();assert.equal(await page.locator('#face').getAttribute('data-frame'),String(frame));
   result.filters=[];
   for(const filter of ['new','idle','interaction','scene']){
    const expected=catalog.clips.filter(clip=>filter==='new'?Boolean(latest&&clip.batch===latest):group(clip)===filter);const beforeClip=await page.locator('#face').getAttribute('data-clip');const beforeFrame=await page.locator('#face').getAttribute('data-frame');
    await page.locator(`[data-candidate-filter=${filter}]`).click();assert.equal(await page.locator(`[data-candidate-filter=${filter}]`).getAttribute('aria-pressed'),'true');
    const options=await page.locator('#clip-select option').evaluateAll(items=>items.map(item=>item.value));
    if(expected.length){assert.deepEqual(options,expected.map(clip=>clip.id));assert.equal(await page.locator('#clip-select').isDisabled(),false);assert.match(await page.locator('#candidate-filter-summary').textContent(),/手動播一次/);if(expected.some(clip=>clip.id===beforeClip)){assert.equal(await page.locator('#face').getAttribute('data-clip'),beforeClip);assert.equal(await page.locator('#face').getAttribute('data-frame'),beforeFrame);}}
    else{assert.equal(await page.locator('#clip-select').isDisabled(),true);assert.match(await page.locator('#candidate-filter-summary').textContent(),/目前沒有畫稿/);assert.equal(await page.locator('#face').getAttribute('data-clip'),beforeClip);assert.equal(await page.locator('#face').getAttribute('data-frame'),beforeFrame);}
    const selected=await page.locator('#face').getAttribute('data-clip');const selectedFrame=await page.locator('#face').getAttribute('data-frame');await page.clock.runFor(30000);assert.equal(await page.evaluate(()=>window.__patrickPreviewShell.report.playing),false);assert.equal(await page.locator('#face').getAttribute('data-clip'),selected);assert.equal(await page.locator('#face').getAttribute('data-frame'),selectedFrame);
    result.filters.push({filter,matchingIds:expected.map(clip=>clip.id),selectedClip:selected,autoplay:false});
   }
   const pending=page.waitForEvent('download');await page.locator('#export-review').click();const download=await pending;const target=path.join(output,'filtered-all-review-export.json');await download.saveAs(target);const exported=JSON.parse(fs.readFileSync(target,'utf8'));assert.equal(exported.clips.length,catalog.clips.length);assert.match(exported.clips.find(clip=>clip.asset===first.id).sections.action.note,/篩選前/);
   await page.locator('[data-candidate-filter=all]').click();await page.locator('#clip-select').selectOption(first.id);assert.match(await page.locator('#review-note').inputValue(),/篩選前/);
   for(const[key,value]of Object.entries(protectedValues))assert.equal(await page.evaluate(k=>localStorage.getItem(k),key),value);
   await ready(page,report.url+'&group=new');assert.equal(await page.locator('[data-candidate-filter=new]').getAttribute('aria-pressed'),'true');
   if(latest)assert.deepEqual(await page.locator('#clip-select option').evaluateAll(items=>items.map(item=>item.value)),catalog.clips.filter(clip=>clip.batch===latest).map(clip=>clip.id));
   await page.screenshot({path:path.join(output,'candidate-filters-desktop.png'),fullPage:true});
  });
  await test('fixed-whitelist-and-main-catalog-unchanged',{viewport:{width:375,height:900}},async(page,result)=>{
   const main=await ready(page,`${address}?review=../../animation/candidates.json`);assert.equal(main.mode,'main');assert.equal(main.catalog,'animation/catalog.json');assert.equal(await page.locator('#candidate-banner').isVisible(),false);assert.equal(await page.locator('#candidate-link').getAttribute('href'),'./?review=candidates');
   const ids=await page.locator('#clip-select option').evaluateAll(items=>items.map(item=>item.value));const mainCatalog=JSON.parse(fs.readFileSync(path.join(root,'animation/catalog.json'),'utf8'));assert.deepEqual(ids,mainCatalog.clips.map(clip=>clip.id));assert.equal(await page.locator('#candidate-filters').isVisible(),false);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
   await ready(page);assert.equal(await page.locator('#candidate-banner').isVisible(),true);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:path.join(output,'mobile-candidates-375.png'),fullPage:true});result.mainClipIds=ids;
  });
 }finally{await browser.close();report.finishedAt=new Date().toISOString();report.passed=report.cases.every(item=>item.passed);fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));}
 if(!report.passed)process.exitCode=1;
})();
