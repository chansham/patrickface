const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const{chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const root=path.resolve(__dirname,'..'),output=path.join(root,'output/playwright/20261008-acceptance');
const base=process.env.PREVIEW_URL||'http://127.0.0.1:8765/';
const auditPath='animation/production-20261007-completion/body-scale-audit.json';
const id='chef-cookie-repair-20261007',audit=JSON.parse(fs.readFileSync(path.join(root,auditPath)));
const entry=audit.clips.find(value=>value.id===id),seed={'patrick.experience.v1':'{"keep":"daily state"}','patrick.size-review.v1':'{"version":1,"notes":{"historic":{"clipID":"focus","text":"保留舊意見","artApproval":false}}}'};
const report={artApproval:false,cases:[]},completionIDs=['chef-cookie-repair-20261007','focus-transition-repair-20261007','charging-cozy-20261007'];fs.mkdirSync(output,{recursive:true});
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
  async function check(name,mutate,body,viewport={width:1440,height:1100}){
    if(process.env.QA_CASE_IDS&&!process.env.QA_CASE_IDS.split(',').includes(name))return;
    console.log('CHECK '+name);const result={name,passed:false};report.cases.push(result);const context=await browser.newContext({viewport}),page=await context.newPage(),errors=[];
    page.on('pageerror',error=>errors.push(error.message));await context.addInitScript(values=>{for(const[key,value]of Object.entries(values))localStorage.setItem(key,value);},seed);
    if(mutate)await page.route('**/'+auditPath,route=>{const changed=structuredClone(audit);mutate(changed.clips.find(value=>value.id===id));return route.fulfill({json:changed});});
    try{await page.goto(base+'size-review/?review=candidates&right='+id);await page.waitForFunction(()=>window.__patrickSizeReview?.status==='ready',{},{timeout:90000});
      const loading=await page.evaluate(id=>({loaded:__patrickSizeReview.clipIDs.includes(id),failures:__patrickSizeReview.failures}),id);assert.equal(loading.loaded,true,`Required clip did not load: ${JSON.stringify(loading)}`);assert.deepEqual(loading.failures,[],'Every current main/candidate source must load without failure');
      await body(page,result);assert.deepEqual(await page.evaluate(()=>Object.fromEntries(Object.entries(localStorage))),seed);assert.deepEqual(errors,[]);result.passed=true;console.log('PASS '+name);
    }catch(error){result.error=error.stack;console.error('FAIL '+name+': '+error.message);fs.writeFileSync(path.join(output,'browser-report.json'),JSON.stringify(report,null,2));await page.screenshot({path:path.join(output,name+'-failure.png'),timeout:10000}).catch(()=>{});}
    finally{await context.close();}
  }
  try{
    await check('actual-coverage-first-last-and-fixed-scale',null,async(page,result)=>{
      const value=await page.evaluate(id=>__patrickSizeReview.evidence(id),id);assert.equal(value.evidenceComplete,true,JSON.stringify(value));assert.equal(value.metrics.faceWidth.measured,7);assert.equal(value.metrics.faceWidth.unknown,5);assert.equal(value.sourceFrameCount,12);assert.equal(value.artApproval,false);
      const box=page.locator('[data-side="1"] .evidence-coverage');assert.match(await box.textContent(),/7\/12 格可量/);assert.match(await box.textContent(),/大 3.3%/);
      await page.locator('#landmarks').check();const first=await page.evaluate(id=>__patrickSizeReview.geometry(id,0,'classic'),id);
      await page.locator('#frame-1').fill('11');await page.locator('#frame-1').dispatchEvent('input');
      const last=await page.evaluate(id=>__patrickSizeReview.geometry(id,11,'classic'),id);assert.equal(first.pixelScale,last.pixelScale);assert.deepEqual(first.anchor,last.anchor);
      assert.equal(await page.locator('[data-side="1"] canvas').first().getAttribute('data-frame'),'11');assert.notEqual(await page.locator('[data-side="1"] canvas').first().getAttribute('data-foot-line'),'');
      result.coverage=value;await page.screenshot({path:path.join(output,'coverage-desktop.png'),fullPage:true});
      result.playbacks=[];
      await page.evaluate(()=>{const original=CanvasRenderingContext2D.prototype.drawImage;window.recordedDraws=[];CanvasRenderingContext2D.prototype.drawImage=function(source,...args){original.call(this,source,...args);if(this.canvas.matches('.large')&&this.canvas.closest('[data-side="1"]')&&source?.dataset?.sourceFrame!==undefined)window.recordedDraws.push({at:performance.now(),frame:Number(source.dataset.sourceFrame),width:source.width,height:source.height,destination:args.slice(-4)});};});
      for(const clipID of completionIDs){
        await page.evaluate(()=>window.recordedDraws=[]);
        await page.locator('#revision-select').selectOption(clipID);await page.locator('#guides').uncheck();
        await page.locator('#compare-grid').screenshot({path:path.join(output,clipID+'-first.png')});
        assert.equal(await page.locator('[data-side="1"] canvas').first().getAttribute('data-frame'),'0','First frame is already rendered when one-shot playback starts');
        await page.locator('#play-pair').click();await page.waitForFunction(()=>!__patrickSizeReview.state.playing,{},{timeout:15000});
        const draws=await page.evaluate(()=>window.recordedDraws),order=draws.map(value=>value.frame).filter((value,i,all)=>i===0||value!==all[i-1]);assert.deepEqual(order,Array.from({length:12},(_,i)=>i));
        assert.ok(draws.every(draw=>draw.width===draws[0].width&&draw.height===draws[0].height&&JSON.stringify(draw.destination)===JSON.stringify(draws[0].destination)),'Every frame keeps exactly the same source canvas size and destination rectangle');
        const memory=await page.evaluate(()=>__patrickSizeReview.memory());assert.ok(memory.retainedFrameCanvases<=12);assert.equal(memory.maxFrameCanvases,12);
        result.playbacks.push({clipID,frames:order,draws,memory});await page.locator('#compare-grid').screenshot({path:path.join(output,clipID+'-last.png')});
      }
      await page.locator('#revision-select').selectOption('focus-transition-repair-20261007');assert.match(await page.locator('[data-side="1"] .known-art-issues').textContent(),/5\.19%/);
    });
    await check('missing-original-frame-blocks-numbers-and-guides',entry=>entry.frames.splice(4,1),async page=>{
      await page.locator('#landmarks').check();assert.equal(await page.locator('[data-side="1"] .evidence-coverage').getAttribute('data-complete'),'false');assert.match(await page.locator('[data-side="1"] .evidence-coverage').textContent(),/第 5 格缺少/);
      assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(),['未能量測','未能量測','未能量測']);assert.equal(await page.locator('[data-side="1"] canvas').first().getAttribute('data-foot-line'),'');
    });
    await check('stale-source-hash-blocks-old-audit',entry=>entry.sourceSha256='0'.repeat(64),async page=>{
      assert.equal(await page.locator('[data-side="1"] .evidence-coverage').getAttribute('data-complete'),'false');assert.match(await page.locator('[data-side="1"] .measurement-source').textContent(),/版本不符/);
      assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(),['未能量測','未能量測','未能量測']);assert.equal(await page.evaluate(()=>__patrickSizeReview.state.playing),false);
    });
    await check('mobile-coverage-readable-and-storage-unchanged',null,async page=>{
      assert.ok(await page.locator('[data-side="1"] .evidence-coverage').isVisible());assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
      await page.locator('[data-side="1"] .evidence-coverage').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(output,'coverage-mobile.png')});
    },{width:390,height:844});
  }finally{await browser.close();fs.writeFileSync(path.join(output,'browser-report.json'),JSON.stringify(report,null,2));}
  if(report.cases.some(value=>!value.passed))process.exitCode=1;
})().catch(error=>{console.error(error);process.exitCode=1;});
