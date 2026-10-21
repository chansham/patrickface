// Disposable real-browser wardrobe review. Does not approve art or change source files.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const root=path.resolve(__dirname,'../..'),out=process.env.QA_OUTPUT||path.join(root,'output/playwright/wardrobe-20261012/browser');
const address=process.env.PREVIEW_URL||'http://127.0.0.1:8765/';
const catalog=JSON.parse(fs.readFileSync(path.join(root,'animation/candidates.json'))),layouts=JSON.parse(fs.readFileSync(path.join(root,'experience/layouts.json'))).layouts;
const ids=(process.env.QA_CLIP_IDS||'raincoat-smooth-20261012').split(',');
fs.mkdirSync(out,{recursive:true});const report={schemaVersion:1,startedAt:new Date().toISOString(),artApproval:false,cases:[]};
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
try{const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(address+`size-review/?review=candidates&left=${ids[0]}&right=${ids.at(-1)}`);
  await page.waitForFunction(()=>['ready','error'].includes(window.__patrickSizeReview?.status));assert.equal(await page.evaluate(()=>__patrickSizeReview.status),'ready');
  const before=await page.evaluate(()=>Object.fromEntries(Object.entries(localStorage)));await page.locator('#guides').uncheck();
  for(const id of ids){const clip=catalog.clips.find(c=>c.id===id),entry={id,passed:false,sourceSHA:clip.sha256,regionsSHA:clip.frameRegions.sha256};report.cases.push(entry);
    await page.locator('[data-tab="compare"]').click();await page.locator('#compare-0').selectOption(clip.comparisonClipId||'yawn');await page.locator('#compare-1').selectOption(id);
    await page.locator('#compare-grid').screenshot({path:path.join(out,id+'-reference-first.png')});
    entry.geometry=await page.evaluate(({id,layouts,count})=>{
      const c=document.createElement('canvas').getContext('2d');
      const zone=(text,center,font)=>{c.font=font;c.textAlign='center';c.textBaseline='middle';const m=c.measureText(text);return[center[0]-m.actualBoundingBoxLeft,center[1]-m.actualBoundingBoxAscent,m.actualBoundingBoxLeft+m.actualBoundingBoxRight,m.actualBoundingBoxAscent+m.actualBoundingBoxDescent];};
      return layouts.map(layout=>({id:layout.id,zones:[{kind:'time',bounds:zone('10:10',layout.timeCenter,`${layout.id==='bold'?600:480} ${layout.timeFontSize}px "Segoe UI",sans-serif`)},{kind:'date',bounds:zone('10/12（週一）',layout.dateCenter,`${layout.dateFontSize}px "Microsoft JhengHei",sans-serif`)},...(layout.informationRect?[{kind:'information',bounds:layout.informationRect}]:[])],frames:Array.from({length:count},(_,i)=>__patrickSizeReview.geometry(id,i,layout.id))}));
    },{id,layouts,count:clip.frameCount});
    for(const layout of entry.geometry){assert.equal(new Set(layout.frames.map(f=>JSON.stringify(f.rect))).size,1);assert.equal(new Set(layout.frames.map(f=>f.pixelScale)).size,1);assert.equal(new Set(layout.frames.map(f=>JSON.stringify(f.anchor))).size,1);
      for(const [i,f]of layout.frames.entries()){const[x,y,w,h]=f.bounds;assert.ok(x>=0&&y>=0&&x+w<=832&&y+h<=992,`${id}/${layout.id}/${i} clipped`);
        for(const z of layout.zones){const[zx,zy,zw,zh]=z.bounds;assert.ok(x+w<=zx||x>=zx+zw||y+h<=zy||y>=zy+zh,`${id}/${layout.id}/${i} overlaps ${z.kind}`);}}
    }
    entry.frames=[];
    for(let i=0;i<clip.frameCount;i++){await page.locator('#frame-1').fill(String(i));await page.locator('#frame-1').dispatchEvent('input');const views=await page.locator('[data-side="1"] canvas').evaluateAll(nodes=>nodes.map(c=>({width:c.getBoundingClientRect().width,frame:c.dataset.frame,rect:c.dataset.rect})));assert.equal(views[0].frame,String(i));assert.equal(views[1].frame,String(i));assert.equal(views[0].rect,views[1].rect);assert.equal(views[1].width,200);entry.frames.push(views);await page.locator('[data-side="1"] canvas').first().screenshot({path:path.join(out,`${id}-frame-${i+1}.png`)});}
    await page.locator('#compare-grid').screenshot({path:path.join(out,id+'-reference-last.png')});
    await page.evaluate(()=>{window.__raincoatObserved=[];window.__raincoatWatching=true;const tick=()=>{if(!__raincoatWatching)return;const i=__patrickSizeReview.state.pair[1].index;if(!__raincoatObserved.length||__raincoatObserved.at(-1).frame!==i)__raincoatObserved.push({frame:i,at:performance.now()});requestAnimationFrame(tick);};requestAnimationFrame(tick);});
    await page.locator('#play-pair').click();await page.waitForFunction(()=>!__patrickSizeReview.state.playing,null,{timeout:15000});
    entry.normal1x=await page.evaluate(()=>{__raincoatWatching=false;return __raincoatObserved;});
    const first=entry.normal1x.findIndex(x=>x.frame===0),sequence=entry.normal1x.slice(first);assert.deepEqual(sequence.map(x=>x.frame),Array.from({length:clip.frameCount},(_,i)=>i));
    entry.normal1x=sequence;entry.sourceOrder=clip.frameIndices;entry.totalMs=clip.durationsMs.reduce((a,b)=>a+b,0);
    const expectedLastStarts=clip.durationsMs.slice(0,-1).reduce((a,b)=>a+b,0),observed=sequence.at(-1).at-sequence[0].at;assert.ok(Math.abs(observed-expectedLastStarts)<250,'real wall-clock 1x drift');
    await page.locator('[data-tab="layouts"]').click();await page.locator('#layout-clip').selectOption(id);await page.locator('#layout-frame').fill('0');await page.locator('#layout-frame').dispatchEvent('input');await page.locator('#layout-grid').screenshot({path:path.join(out,id+'-four-layouts.png')});entry.passed=true;
  }
  await page.locator('[data-tab="compare"]').click();await page.locator('#compare-0').selectOption(ids[0]);await page.locator('#compare-1').selectOption(ids.at(-1));for(const side of [0,1]){await page.locator('#frame-'+side).fill('0');await page.locator('#frame-'+side).dispatchEvent('input');}
  await page.locator('#compare-grid').screenshot({path:path.join(out,'batch-first.png')});
  assert.deepEqual(await page.evaluate(()=>Object.fromEntries(Object.entries(localStorage))),before);assert.deepEqual(errors,[]);report.errors=errors;report.observedFrameCount=report.cases.reduce((sum,item)=>sum+item.normal1x.length,0);report.layoutFrameChecks=report.observedFrameCount*4;
}catch(e){report.error=e.stack;throw e;}finally{report.finishedAt=new Date().toISOString();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
