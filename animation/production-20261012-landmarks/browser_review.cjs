// Existing repository Playwright QA style; no @playwright/test or server changes.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const{chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/playwright/20261012-landmarks');
const ids=['exercise-repair-20261006','running-first-20261006','charging-cozy-20261007'];
const expected=[[15,15,15],[6,15,0],[10,11,0]],report={artApproval:false,cases:[],errors:[]};fs.mkdirSync(out,{recursive:true});
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
  const context=await browser.newContext({viewport:{width:1440,height:1100}}),page=await context.newPage();
  page.on('pageerror',error=>report.errors.push(error.message));
  try{
    await page.goto('http://127.0.0.1:8765/size-review/?review=candidates&right='+ids[0]+'&v=20261012-landmarks');
    await page.waitForFunction(()=>window.__patrickSizeReview?.status==='ready',{},{timeout:120000});
    assert.deepEqual(await page.evaluate(()=>__patrickSizeReview.failures),[]);
    const sources=await page.evaluate(()=>__patrickSizeReview.auditSources);assert.ok(sources.some(s=>s.path==='animation/production-20261012-landmarks/body-scale-audit.json'&&s.loaded));
    await page.locator('#landmarks').check();await page.locator('#guides').uncheck();
    for(let i=0;i<ids.length;i++){
      const id=ids[i],evidence=await page.evaluate(id=>__patrickSizeReview.evidence(id),id);
      assert.equal(evidence.evidenceComplete,true);assert.equal(evidence.artApproval,false);
      assert.deepEqual(['faceWidth','eyeSeparation','eyeToFoot'].map(k=>evidence.metrics[k].measured),expected[i]);
      await page.locator('#revision-select').selectOption(id);
      await page.locator('[data-side="1"]').screenshot({path:path.join(out,id+'-source-lines.png')});
      const first=await page.evaluate(id=>__patrickSizeReview.geometry(id,0,'classic'),id);
      const last=await page.evaluate(id=>__patrickSizeReview.geometry(id,id==='charging-cozy-20261007'?11:15,'classic'),id);
      assert.equal(first.pixelScale,last.pixelScale);assert.deepEqual(first.anchor,last.anchor);
      const closed=id==='charging-cozy-20261007'?7:12;
      await page.locator('#frame-1').fill(String(closed));await page.locator('#frame-1').dispatchEvent('input');
      assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(),['未能量測','未能量測','未能量測']);
      assert.equal(await page.locator('[data-side="1"] canvas').first().getAttribute('data-foot-line'),'');
      report.cases.push({id,evidence,closedFrameUnknown:true,fixedScale:true});
    }
    // Frame 9's battery overlaps the face: eye line remains, full face width does not.
    await page.locator('#frame-1').fill('8');await page.locator('#frame-1').dispatchEvent('input');
    const numbers=await page.locator('[data-side="1"] .measurement-row strong').allTextContents();
    assert.equal(numbers[0],'未能量測');assert.notEqual(numbers[1],'未能量測');assert.equal(numbers[2],'未能量測');
    await page.locator('[data-side="1"]').screenshot({path:path.join(out,'cozy-occluded-face-stays-unknown.png')});
    await page.locator('[data-tab="layouts"]').click();await page.locator('#layout-clip').selectOption(ids[0]);
    await page.locator('#layout-grid').screenshot({path:path.join(out,'exercise-four-layouts-with-footer.png')});
    await page.setViewportSize({width:390,height:844});await page.locator('[data-tab="compare"]').click();
    await page.locator('#revision-select').selectOption(ids[0]);await page.locator('[data-side="1"] .evidence-coverage').scrollIntoViewIfNeeded();
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
    await page.screenshot({path:path.join(out,'coverage-mobile.png')});
    assert.deepEqual(report.errors,[]);report.passed=true;
  }catch(error){report.passed=false;report.failure=error.stack;process.exitCode=1;}
  finally{await context.close();await browser.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:report.passed,cases:report.cases.length,failure:report.failure,errors:report.errors}));}
})();
