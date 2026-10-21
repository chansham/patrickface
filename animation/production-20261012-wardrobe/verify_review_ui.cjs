const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const out=path.resolve(__dirname,'../../output/playwright/20261012-wardrobe-final');
fs.mkdirSync(out,{recursive:true});
const report={artApproval:false,errors:[],cases:[]};
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
const context=await browser.newContext({viewport:{width:1440,height:1100},acceptDownloads:true});const page=await context.newPage();
page.on('pageerror',e=>report.errors.push(e.message));
try{
 await page.goto('http://127.0.0.1:8765/size-review/?review=candidates&right=raincoat-smooth-20261012&v=20261012-wardrobe1');
 await page.waitForFunction(()=>window.__patrickSizeReview?.status==='ready',null,{timeout:120000});
 assert.deepEqual(await page.evaluate(()=>__patrickSizeReview.failures),[]);
 assert.deepEqual(await page.evaluate(()=>__patrickSizeReview.state.pair.map(p=>p.id)),['raincoat-first-20261012','raincoat-smooth-20261012']);
 report.cases.push({name:'candidate-to-candidate-reference',passed:true});
 const specs=[['raincoat-smooth-20261012',[12,12,12]],['sport-towel-first-20261012',[4,7,7]],['exercise-repair-20261006',[15,15,15]],['running-first-20261006',[6,15,0]],['charging-cozy-20261007',[10,11,0]],['raincoat-first-20261012',[7,7,7]]];
 for(const[id,counts]of specs){
   const e=await page.evaluate(id=>__patrickSizeReview.evidence(id),id);
   assert.equal(e.evidenceComplete,true,id);assert.equal(e.artApproval,false);
   assert.deepEqual(['faceWidth','eyeSeparation','eyeToFoot'].map(k=>e.metrics[k].measured),counts,id);
   report.cases.push({name:'audit-source-priority',id,counts,passed:true});
 }
 await page.locator('#guides').uncheck();await page.locator('#landmarks').check();
 await page.locator('#compare-grid').screenshot({path:path.join(out,'raincoat-original-and-revision.png')});
 await page.locator('#revision-select').selectOption('sport-towel-first-20261012');
 await page.locator('[data-side="1"]').screenshot({path:path.join(out,'sport-towel-audit.png')});
 // A towel obscures the face section but leaves the two eye rims visible.
 await page.locator('#frame-1').fill('2');await page.locator('#frame-1').dispatchEvent('input');
 let vals=await page.locator('[data-side="1"] .measurement-row strong').allTextContents();
 assert.equal(vals[0],'未能量測');assert.notEqual(vals[1],'未能量測');assert.notEqual(vals[2],'未能量測');
 // Completely closed eyes retain unknown anatomy; feedback still targets source 5.
 await page.locator('#frame-1').fill('4');await page.locator('#frame-1').dispatchEvent('input');
 assert.deepEqual(await page.locator('[data-side="1"] .measurement-row strong').allTextContents(),['未能量測','未能量測','未能量測']);
 await page.locator('[data-side="1"] .mark-frame').last().click();
 await page.locator('[name="frame-issue"][value="motion"]').check();
 await page.locator('#frame-note').fill('QA: 檢查閉眼前後接續');
 assert.match(await page.locator('#frame-target').innerText(),/來源第5格/);
 const downloadEvent=page.waitForEvent('download');await page.locator('#export').click();const download=await downloadEvent;
 const file=path.join(out,'sample-export.json');await download.saveAs(file);
 const value=JSON.parse(fs.readFileSync(file,'utf8')),note=value.frameNotes[0];
 assert.equal(note.clipID,'sport-towel-first-20261012');assert.equal(note.sourceFrameNumber,5);assert.equal(note.artApproval,false);
 assert.equal(note.sourceSha256,'01e212bf5c64471fec5f6c836e88e54406803562da0f8e2a0eea4a2e9d1abead');
 report.cases.push({name:'new-source-unknowns-and-exact-frame-export',passed:true});
 await page.setViewportSize({width:390,height:844});await page.locator('#frame-review').screenshot({path:path.join(out,'new-sport-frame-marker-390.png')});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 assert.deepEqual(report.errors,[]);report.passed=true;
}catch(e){report.passed=false;report.failure=e.stack;process.exitCode=1;}
finally{await context.close();await browser.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:report.passed,cases:report.cases.length,failure:report.failure,errors:report.errors}));}
})();
