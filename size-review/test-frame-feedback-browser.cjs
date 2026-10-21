const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE || 'playwright');
const root = path.resolve(__dirname, '..');
const output = process.env.QA_OUTPUT || path.join(root, 'output/playwright/20261012-frame-feedback');
const address = process.env.PREVIEW_URL || 'http://127.0.0.1:8765/';
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'animation/catalog.json')));
const candidates = JSON.parse(fs.readFileSync(path.join(root, 'animation/candidates.json')));
const bath = catalog.clips.find(clip => clip.id === 'bath');
const candidate = candidates.clips.find(clip => clip.comparisonClipId && clip.frameRegions);
const key = 'patrick.frame-review.v1';
const legacy = { clipID: 'bath', verdict: 'revise', text: '既有整段觀察，不可刪除', artApproval: false };
const seeded = {
  'patrick.size-review.v1': JSON.stringify({version:1,notes:{'legacy-fixture':legacy}}),
  'patrick.animation-review.patrick-bedtime-yawn-v1.v2': JSON.stringify({verdict:'revise',text:'保留舊審稿'}),
  'patrick.experience.v1': JSON.stringify({fixture:'unchanged daily state'})
};
const report = {startedAt:new Date().toISOString(),artApproval:false,cases:[]};
fs.mkdirSync(output,{recursive:true});
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
  const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});
  await context.addInitScript(({seed,origin})=>{
    if(location.origin!==origin)return;
    if(!localStorage.getItem('frame-feedback-qa-seeded')){
      for(const[k,v]of Object.entries(seed))localStorage.setItem(k,v);
      localStorage.setItem('frame-feedback-qa-seeded','yes');
    }
  },{seed:seeded,origin:new URL(address).origin});
  const page=await context.newPage(),errors=[];
  context.on('page',p=>p.on('pageerror',e=>errors.push(e.message)));
  page.on('pageerror',e=>errors.push(e.message));
  const stored=p=>p.evaluate(k=>JSON.parse(localStorage.getItem(k))?.notes||{},key);
  async function ready(p){await p.waitForFunction(()=>window.__patrickSizeReview?.status==='ready',{},{timeout:60000});assert.deepEqual(await p.evaluate(()=>__patrickSizeReview.failures),[]);}
  async function mark(p,id='bath',index=4){
    await p.locator('[data-tab="layouts"]').click();await p.locator('#layout-clip').selectOption(id);
    await p.locator('#layout-frame').fill(String(index));await p.locator('#layout-frame').dispatchEvent('input');
    await p.locator('#layout-grid [data-layout="activity"] .mark-frame').last().click();
  }
  async function exportNotes(p,name){const[download]=await Promise.all([p.waitForEvent('download'),p.locator('#export').click()]);const target=path.join(output,name+'.json');await download.saveAs(target);return JSON.parse(fs.readFileSync(target));}
  async function unchanged(p){for(const[k,v]of Object.entries(seeded))assert.equal(await p.evaluate(k=>localStorage.getItem(k),k),v);}
  async function check(name,body){const result={name,passed:false};report.cases.push(result);try{await body(result);result.passed=true;console.log('PASS '+name);}catch(error){result.error=error.stack;console.error('FAIL '+name+': '+error.message);await page.screenshot({path:path.join(output,name+'-failure.png'),fullPage:true}).catch(()=>{});throw error;}}
  try{
    await page.goto(address+'size-review/');await ready(page);
    await check('source-frame-layout-and-reload',async result=>{
      assert.equal(bath.frameIndices[4],5,'Fixture requires the real omitted original bath frame');
      await mark(page);await page.locator('[name=frame-issue][value=eyes]').check();await page.locator('[name=frame-issue][value=outfit]').check();await page.locator('#frame-note').fill('來源第六格：眼皮和泡澡道具需要確認。');
      let rows=Object.values(await stored(page));assert.equal(rows.length,1);const note=rows[0];
      assert.equal(note.clipID,bath.id);assert.equal(note.sourceSha256,bath.sha256);assert.equal(note.regionsSha256,bath.frameRegions.sha256);assert.equal(note.playbackFrame,4);assert.equal(note.sourceFrame,5);assert.equal(note.playbackFrameNumber,5);assert.equal(note.sourceFrameNumber,6);assert.equal(note.layoutID,'activity');assert.equal(note.viewportWidth,200);assert.equal(note.schemaVersion,1);assert.deepEqual(note.issueTypes,['eyes','outfit']);assert.ok(Date.parse(note.createdAt));assert.ok(Date.parse(note.updatedAt));
      await page.locator('#layout-frame').fill('0');await page.locator('#layout-frame').dispatchEvent('input');assert.match(await page.locator('#frame-target').textContent(),/來源第6格/);
      await page.reload();await ready(page);await page.locator('#frame-notes button').first().click();assert.equal(await page.locator('#frame-note').inputValue(),note.text);assert.equal(await page.locator('#marked-frame').isVisible(),true);await unchanged(page);
      result.record=note;await page.locator('#frame-review').screenshot({path:path.join(output,'frame-marker-desktop.png')});
    });
    await check('click-freezes-playing-frame',async result=>{
      await page.locator('[data-tab="compare"]').click();await page.locator('#compare-1').selectOption('bath');await page.locator('#play-pair').click();
      assert.equal(await page.evaluate(()=>__patrickSizeReview.state.playing),true);
      await page.locator('[data-side="1"] .mark-frame').last().click();assert.equal(await page.evaluate(()=>__patrickSizeReview.state.playing),false);
      const target=await page.locator('#frame-target').textContent();await page.waitForTimeout(400);assert.equal(await page.locator('#frame-target').textContent(),target);result.selected=target;
    });
    await check('two-tabs-delete-add-export-without-resurrection',async result=>{
      const peer=await context.newPage();await peer.goto(address+'size-review/');await ready(peer);
      await page.locator('#frame-notes button').first().click();await page.locator('#frame-remove').click();await peer.waitForFunction(()=>document.querySelector('#frame-notes').children.length===0);
      await mark(peer,'pet',1);await peer.locator('[name=frame-issue][value=motion]').check();await peer.locator('#frame-note').fill('另一分頁新增的收手接續');
      await page.waitForFunction(()=>document.querySelector('#frame-notes').textContent.includes('另一分頁新增'));
      assert.equal(await page.locator('#frame-note').inputValue(),'','Storage events must not rewrite the open editor');
      await mark(page,'bath',2);await page.locator('[name=frame-issue][value=crop]').check();await page.locator('#frame-note').fill('另外一格裁剪');
      const rows=Object.values(await stored(page));assert.equal(rows.length,2);assert.ok(!rows.some(n=>n.clipID==='bath'&&n.sourceFrame===5));assert.ok(rows.some(n=>n.clipID==='pet'));
      const exported=await exportNotes(page,'two-tabs-export');assert.equal(exported.frameNotes.length,2);assert.deepEqual(exported.notes,[legacy]);assert.equal(exported.frameReviewSchemaVersion,1);assert.ok(Date.parse(exported.exportedAt));await unchanged(page);result.exported=exported.frameNotes.map(n=>({clipID:n.clipID,sourceFrameNumber:n.sourceFrameNumber}));await peer.close();
    });
    await check('same-atlas-new-version-isolated-and-old-source-retained',async result=>{
      const prior=Object.values(await stored(page)).find(n=>n.clipID==='bath');
      const variant=structuredClone(catalog);variant.clips.find(c=>c.id==='bath').version=Number(bath.version)+100;
      await page.route('**/animation/catalog.json*',route=>route.fulfill({contentType:'application/json',body:JSON.stringify(variant)}));await page.reload();await ready(page);
      const old=page.locator('#frame-notes li').filter({hasText:'另外一格裁剪'});assert.match(await old.textContent(),/舊版本/);await old.locator('button').click();assert.equal(await page.locator('#marked-frame').isVisible(),false);assert.equal(await page.locator('#frame-preview-unavailable').isVisible(),true);
      await mark(page,'bath',2);assert.equal(await page.locator('#frame-note').inputValue(),'');await page.locator('[name=frame-issue][value=size]').check();await page.locator('#frame-note').fill('同atlas新版本的獨立標記');
      const exported=await exportNotes(page,'versioned-export');const rows=exported.frameNotes.filter(n=>n.clipID==='bath');assert.equal(rows.length,2);assert.ok(rows.some(n=>n.clipVersion===prior.clipVersion&&n.text===prior.text));assert.notEqual(rows[0].clipVersion,rows[1].clipVersion);result.versions=rows.map(n=>n.clipVersion);
      await page.unroute('**/animation/catalog.json*');
    });
    await check('quota-failure-keeps-local-note-and-includes-it-in-export',async result=>{
      await page.reload();await ready(page);await mark(page,'bath',1);
      await page.evaluate(k=>{const original=Storage.prototype.setItem;window.restoreFeedbackStorage=()=>Storage.prototype.setItem=original;Storage.prototype.setItem=function(key,value){if(key===k)throw new DOMException('fixture full','QuotaExceededError');return original.call(this,key,value);};},key);
      await page.locator('[name=frame-issue][value=motion]').check();await page.locator('#frame-note').fill('儲存額滿時也要可匯出');assert.match(await page.locator('#frame-save-state').textContent(),/不能保存/);
      assert.ok(!Object.values(await stored(page)).some(n=>n.text==='儲存額滿時也要可匯出'));
      const exported=await exportNotes(page,'quota-export');assert.ok(exported.frameNotes.some(n=>n.text==='儲存額滿時也要可匯出'));await page.evaluate(()=>restoreFeedbackStorage());await page.locator('#frame-save').click();assert.ok(Object.values(await stored(page)).some(n=>n.text==='儲存額滿時也要可匯出'));result.unsavedIncluded=true;
    });
    await check('candidate-review-mobile-390-and-daily-state-untouched',async result=>{
      assert.ok(candidate);await page.setViewportSize({width:390,height:844});await page.goto(address+`size-review/?review=candidates&right=${encodeURIComponent(candidate.id)}`);await ready(page);await mark(page,candidate.id,0);
      await page.locator('[name=frame-issue][value=eyes]').check();await page.locator('#frame-note').fill('待審候選第1格，眼睛顏色待修。');
      const row=Object.values(await stored(page)).find(n=>n.clipID===candidate.id);assert.equal(row.catalog,'candidates');assert.equal(row.sourceSha256,candidate.sha256);assert.equal(row.sourceFrameNumber,(candidate.frameIndices?.[0]??0)+1);assert.equal(row.viewportWidth,200);assert.equal(row.artApproval,false);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.equal(await page.evaluate(()=>__patrickSizeReview.state.playing),false);await unchanged(page);
      await page.locator('#frame-review').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(output,'frame-marker-mobile-390.png')});await page.locator('#frame-review').screenshot({path:path.join(output,'frame-editor-mobile-390-full.png')});
      const exported=await exportNotes(page,'final-export');assert.deepEqual(exported.notes,[legacy]);assert.ok(exported.frameNotes.some(n=>n.catalog==='candidates'));assert.ok(exported.frameNotes.some(n=>n.clipVersion===Number(bath.version)+100));result.candidateID=candidate.id;result.exportedCount=exported.frameNotes.length;
    });
    assert.deepEqual(errors,[]);report.passed=true;
  }catch(error){report.error=error.stack;process.exitCode=1;}
  finally{report.finishedAt=new Date().toISOString();report.pageErrors=errors;fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));await context.close();await browser.close();}
})();
