const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const root=path.resolve(__dirname,'..');
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8').replace(/^\uFEFF/,''));
const data=read('animation/production-20261012-review/art-priorities.json');
const clips=read('animation/candidates.json').clips;
const out=path.join(root,'output/playwright/20261012-review/known-issues');fs.mkdirSync(out,{recursive:true});
const report={cases:[],errors:[],artApproval:false};
const pass=(name,extra={})=>report.cases.push({name,...extra,passed:true});
const base='http://127.0.0.1:8765/size-review/';
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
 const context=await browser.newContext({viewport:{width:1440,height:1100},reducedMotion:'reduce'});
 const page=await context.newPage();page.on('pageerror',e=>report.errors.push(e.message));
 const saved={ 'patrick.pet.v1':'{"keep":"daily"}', 'patrick.frame-review.v1':'{"version":1,"notes":{}}', 'patrick.size-review.v1':'{"version":1,"notes":{}}' };
 await context.addInitScript(values=>{for(const[k,v]of Object.entries(values))localStorage.setItem(k,v);},saved);
 const ready=()=>page.waitForFunction(()=>window.__patrickSizeReview?.status==='ready',null,{timeout:120000});
 try{
   await page.goto(base+'?review=candidates&issues=1');await ready();
   assert.equal(await page.locator('#known-issues').evaluate(el=>el.open),true);
   assert.equal(await page.locator('#known-issues-list>li').count(),data.items.length);
   pass('known-issues-loaded-separately-from-user-notes',{items:data.items.length});
   await page.locator('[data-side="1"] .mark-frame').last().click();
   await page.locator('#frame-note').fill('Previously saved opinion must survive looking through the issue list.');
   saved['patrick.frame-review.v1']=await page.evaluate(()=>localStorage.getItem('patrick.frame-review.v1'));
   let visited=0;
   for(let itemIndex=0;itemIndex<data.items.length;itemIndex++){
     const item=data.items[itemIndex],clip=clips.find(c=>c.id===item.clipID);
     for(const sourceFrame of [...new Set(item.sourceFrames)]){
       await page.locator('#known-issues-list>li').nth(itemIndex).locator(`button[data-source-frame="${sourceFrame}"]`).click();
       const right=await page.evaluate(()=>__patrickSizeReview.state.pair[1]);
       assert.deepEqual(right,{id:clip.id,index:clip.frameIndices.indexOf(sourceFrame-1)});
       assert.equal(await page.locator('#frame-1').inputValue(),String(right.index));
       const target=await page.locator('[data-side="1"] canvas').last().evaluate(c=>c.reviewTarget);
       assert.equal(target.sourceFrame,sourceFrame-1);assert.equal(target.sourceSha256,item.sourceSha256);visited++;
     }
   }
   for(const[k,v]of Object.entries(saved))assert.equal(await page.evaluate(key=>localStorage.getItem(key),k),v);
   pass('every-listed-source-frame-locates-without-writing-opinions',{visited});
   await page.locator('#known-issues-kind').selectOption('eyes');
   assert.equal(await page.locator('#known-issues-list>li').count(),data.items.filter(i=>i.issueType==='eyes').length);
   assert.deepEqual(await page.locator('#known-issues-list>li').evaluateAll(rows=>[...new Set(rows.map(r=>r.dataset.kind))]),['eyes']);
   pass('eye-problems-filter');
   await page.locator('#known-issues').screenshot({path:path.join(out,'eye-issues-desktop.png')});
   await page.setViewportSize({width:390,height:844});
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
   await page.locator('#known-issues').screenshot({path:path.join(out,'eye-issues-390.png')});
   pass('390px-no-overflow');
   const reordered=clips.find(c=>c.frameIndices?.some((n,i)=>n!==i));assert.ok(reordered);
   const playbackIndex=reordered.frameIndices.findIndex((n,i)=>n!==i),sourceFrame=reordered.frameIndices[playbackIndex]+1;
   const query=new URLSearchParams({review:'candidates',right:reordered.id,sourceFrame:String(sourceFrame),sourceSha256:reordered.sha256});
   await page.goto(base+'?'+query);await ready();
   assert.deepEqual(await page.evaluate(()=>__patrickSizeReview.state.pair[1]),{id:reordered.id,index:playbackIndex});
   pass('deep-link-resolves-source-order-not-playback-order',{clip:reordered.id,sourceFrame,playbackFrame:playbackIndex+1});
   query.set('sourceSha256','0'.repeat(64));await page.goto(base+'?'+query);await ready();
   assert.match(await page.locator('#known-issues-status').textContent(),/版本不同/);
   assert.equal(await page.evaluate(()=>__patrickSizeReview.state.pair[1].index),0);
   pass('stale-deep-link-does-not-mark-new-image');
   const stale=structuredClone(data);stale.items[0].sourceSha256='0'.repeat(64);
   await page.route('**/art-priorities.json',route=>route.fulfill({json:stale}));
   await page.goto(base+'?review=candidates&issues=1');await ready();
   const first=page.locator('#known-issues-list>li').first();
   assert.ok(await first.locator('button').evaluateAll(buttons=>buttons.every(b=>b.disabled)));
   assert.match(await first.textContent(),/定位已停用/);pass('stale-item-keeps-text-and-disables-navigation');
   await page.unroute('**/art-priorities.json');
   await page.route('**/art-priorities.json',route=>route.fulfill({status:503,body:'unavailable'}));
   await page.goto(base+'?review=candidates&issues=1');await ready();
   assert.match(await page.locator('#known-issues-status').textContent(),/暫時無法載入/);
   assert.ok(await page.locator('#compare-grid canvas').count());pass('queue-failure-does-not-block-existing-review');
   await page.unroute('**/art-priorities.json');await page.goto(base);await ready();
   assert.equal(await page.locator('#known-issues').isVisible(),false);pass('daily-view-has-no-candidate-queue');
   assert.deepEqual(report.errors,[]);report.passed=true;
 }catch(e){report.passed=false;report.failure=e.stack;process.exitCode=1;}
 finally{await context.close();await browser.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:report.passed,cases:report.cases.length,errors:report.errors,failure:report.failure}));}
})();
