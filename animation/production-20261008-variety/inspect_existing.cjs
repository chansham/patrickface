// Fresh foreground 1x and shared-stage evidence for three existing sources.
// Never edits PNGs, source regions, scales, candidate catalogs or product UI.
const {chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),base=process.env.PREVIEW_URL||'http://127.0.0.1:8765/';
const ids=['exercise-repair-20261006','running-first-20261006','charging-cozy-20261007'];
const catalog=JSON.parse(fs.readFileSync(path.join(root,'animation/candidates.json'))),clips=ids.map(id=>catalog.clips.find(c=>c.id===id));
assert.ok(clips.every(Boolean));
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const evidence={schemaVersion:1,inspectedAt:new Date().toISOString(),scope:'Three existing candidate sources, fresh real-time playback and shared200px stage',artApproval:false,
  candidateCatalogSha256:sha(fs.readFileSync(path.join(root,'animation/candidates.json'))),technical:{},clips:[]};
const output=path.join(root,'output/playwright/20261008-active-inspection');fs.mkdirSync(output,{recursive:true});
const esc=v=>String(v).replace(/[&<>\"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));
(async()=>{
 let browser;
 try{
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
  const page=await browser.newPage({viewport:{width:1020,height:1200}});
  // A plain repository directory listing has no product renderer to load the full catalog.
  await page.goto(base+'animation/production-20261008-variety/',{waitUntil:'domcontentloaded'});
  await page.setContent('<meta charset="utf-8"><style>body{background:#17141c;color:#eee;font:16px system-ui;margin:24px}.board{display:flex;gap:20px}canvas{width:200px;height:auto;background:#070609;border-radius:28px}h1{font-size:24px}p,small{color:#cbb4d1}</style><h1>既有核心素材重新覆核</h1><p>同一832×992舞台，200px內容寬；既有固定整段倍率；沒有逐格fit。</p><section class="board"></section>');
  const setup=await page.evaluate(async({clips,master,base})=>{
   const {loadClip,frameGeometry}=await import(base+'size-review/render-core.js?v=20261006-size5');
   const {frameAt}=await import(base+'preview/player-core.js?v=20261006-layouts1');
   const layouts=(await(await fetch(base+'experience/layouts.json')).json()).layouts;
   const loaded=[];for(const c of clips)loaded.push(await loadClip(c,new URL(base),new Map()));
   const canvases=loaded.map(c=>{const box=document.createElement('article'),label=document.createElement('h2'),canvas=document.createElement('canvas'),note=document.createElement('p');label.textContent=c.title;label.style.fontSize='16px';canvas.width=832;canvas.height=992;note.className='frame';box.append(label,canvas,note);document.querySelector('.board').append(box);return canvas;});
   function draw(ci,index,layout=layouts[0]){const c=loaded[ci],g=frameGeometry(c,index,master,layout),canvas=canvases[ci],ctx=canvas.getContext('2d');ctx.fillStyle='#070609';ctx.fillRect(0,0,832,992);ctx.drawImage(g.source,...g.rect);ctx.fillStyle='#faf6fb';ctx.textAlign='center';ctx.textBaseline='middle';ctx.font=`${layout.id==='bold'?600:480} ${layout.timeFontSize}px "Segoe UI", sans-serif`;ctx.fillText('10:10',...layout.timeCenter);ctx.fillStyle='#ab99b5';ctx.font=`${layout.dateFontSize}px "Microsoft JhengHei", sans-serif`;ctx.fillText('10/8（週四）',...layout.dateCenter);if(layout.informationRect){const[x,y]=layout.informationRect;ctx.textAlign='left';ctx.font='42px "Microsoft JhengHei",sans-serif';ctx.fillText('陪伴倒數',x+24,y+100);ctx.font='72px "Segoe UI",sans-serif';ctx.fillText('05:00',x+24,y+180);ctx.font='38px "Microsoft JhengHei",sans-serif';ctx.fillText('進行中',x+24,y+255);ctx.font='42px "Microsoft JhengHei",sans-serif';ctx.fillText('飽足 60%',x+24,y+360);}canvas.dataset.frame=String(index);canvas.parentElement.querySelector('.frame').textContent=`第${index+1}/${c.frameCount}格 · ${layout.title}`;return g;}
   const textctx=document.createElement('canvas').getContext('2d');
   function textBounds(text,center,font){textctx.font=font;textctx.textAlign='center';textctx.textBaseline='middle';const m=textctx.measureText(text);return[center[0]-m.actualBoundingBoxLeft,center[1]-m.actualBoundingBoxAscent,m.actualBoundingBoxLeft+m.actualBoundingBoxRight,m.actualBoundingBoxAscent+m.actualBoundingBoxDescent];}
   const checks=loaded.map((c,ci)=>({id:c.id,sourceSha256:c.sha256,regionsSha256:c.frameRegions.sha256,scale:c.scale,frameCount:c.frameCount,
     layouts:layouts.map(l=>{const zones=[{id:'time',bounds:textBounds('10:10',l.timeCenter,`${l.id==='bold'?600:480} ${l.timeFontSize}px "Segoe UI", sans-serif`)},{id:'date',bounds:textBounds('10/8（週四）',l.dateCenter,`${l.dateFontSize}px "Microsoft JhengHei", sans-serif`)}];if(l.informationRect)zones.push({id:'information',bounds:l.informationRect});return{id:l.id,zones,frames:Array.from({length:c.frameCount},(_,i)=>{const g=frameGeometry(c,i,master,l);return{sourceFrame:g.sourceIndex+1,rect:g.rect,bounds:g.bounds,anchor:g.anchor,pixelScale:g.pixelScale};})};})}));
   loaded.forEach((c,i)=>draw(i,0));
   window.inspect={loaded,canvases,draw,layouts,checks,async play(ci){const c=loaded[ci],duration=c.durationsMs.reduce((a,b)=>a+b,0),frames=[];let last=-1;const started=performance.now();await new Promise(resolve=>{function tick(now){const elapsed=now-started,index=frameAt(c,elapsed);if(index!==last){last=index;draw(ci,index);const copy=document.createElement('canvas');copy.width=200;copy.height=238;copy.getContext('2d').drawImage(canvases[ci],0,0,200,238);frames.push({sourceFrame:index+1,elapsedMs:elapsed,png:copy.toDataURL('image/png')});}if(elapsed>=duration){resolve();return;}requestAnimationFrame(tick);}requestAnimationFrame(tick);});return{frames,durationMs:duration,stoppedFrame:Number(canvases[ci].dataset.frame)+1};}};
   return checks;
  },{clips,master:catalog.master,base});
  await page.locator('.board').screenshot({path:path.join(output,'common-stage-first-200px.png')});
  let layoutFrames=0;
  for(const item of setup){const c=clips.find(c=>c.id===item.id);assert.equal(sha(fs.readFileSync(path.join(root,c.atlas))),item.sourceSha256);assert.equal(sha(fs.readFileSync(path.join(root,c.frameRegions.path))),item.regionsSha256);
   for(const l of item.layouts){assert.equal(new Set(l.frames.map(f=>JSON.stringify(f.rect))).size,1);assert.equal(new Set(l.frames.map(f=>JSON.stringify(f.anchor))).size,1);assert.equal(new Set(l.frames.map(f=>f.pixelScale)).size,1);
    for(const f of l.frames){layoutFrames++;const[x,y,w,h]=f.bounds;f.outsideStage=x<0||y<0||x+w>832||y+h>992;f.overlaps=l.zones.filter(z=>{const[a,b,c,d]=z.bounds;return x+w>a&&x<a+c&&y+h>b&&y<b+d;}).map(z=>z.id);}}
  }
  for(let ci=0;ci<clips.length;ci++){
   await page.bringToFront();const live=await page.evaluate(ci=>inspect.play(ci),ci);
   assert.deepEqual(live.frames.map(f=>f.sourceFrame),Array.from({length:clips[ci].frameCount},(_,i)=>i+1));assert.equal(live.stoppedFrame,clips[ci].frameCount);
   await page.waitForTimeout(550);assert.equal(await page.evaluate(ci=>Number(inspect.canvases[ci].dataset.frame)+1,ci),clips[ci].frameCount);
   const sheet=await browser.newPage({viewport:{width:960,height:1200}});
   await sheet.setContent(`<meta charset="utf-8"><style>body{margin:24px;background:#18151e;color:#eee;font:14px system-ui}h1{font-size:23px}.grid{display:grid;grid-template-columns:repeat(4,200px);gap:20px}img{width:200px;border-radius:24px}small{display:block;margin:6px 0;color:#cdb6cf}</style><h1>${esc(clips[ci].title)} · 本輪真實1×重新擷取</h1><p>每次實際畫格變化擷取；200px同舞台，非逐格fit；原畫仍待審。</p><div class="grid">${live.frames.map(f=>`<article><img src="${f.png}"><small>第${f.sourceFrame}格 · ${Math.round(f.elapsedMs)}ms</small></article>`).join('')}</div>`);
   const sheetname=clips[ci].id+'-live-1x-200px.png';await sheet.screenshot({path:path.join(output,sheetname),fullPage:true});await sheet.close();
   evidence.clips.push({...setup[ci],atlas:clips[ci].atlas,live:{durationMs:live.durationMs,stoppedAtLast:true,noAutomaticLoopObserved:true,frames:live.frames.map(({png,...f})=>f)},frameSheet:'output/playwright/20261008-active-inspection/'+sheetname});
  }
  await page.bringToFront();await page.locator('.board').screenshot({path:path.join(output,'common-stage-last-200px.png')});
  for(const layout of setup[0].layouts){await page.evaluate(id=>inspect.loaded.forEach((c,i)=>inspect.draw(i,Math.floor(c.frameCount/2),inspect.layouts.find(l=>l.id===id))),layout.id);await page.locator('.board').screenshot({path:path.join(output,'common-stage-'+layout.id+'-middle-200px.png')});}
  evidence.technical={sourceHashesMatch:true,oneScaleAndAnchorPerClip:true,realTimePlaybackFrames:evidence.clips.reduce((n,c)=>n+c.frameCount,0),fourLayoutFrameChecks:layoutFrames,
   outsideStageCount:evidence.clips.flatMap(c=>c.layouts.flatMap(l=>l.frames)).filter(f=>f.outsideStage).length,textDateInfoOverlapCount:evidence.clips.flatMap(c=>c.layouts.flatMap(l=>l.frames)).filter(f=>f.overlaps.length).length};
  evidence.status='fresh-technical-evidence-complete-manual-art-review-pending';
 }catch(error){evidence.status='incomplete';evidence.error=error.stack;process.exitCode=1;console.error(error);}
 finally{if(browser)await browser.close();fs.writeFileSync(path.join(__dirname,'inspection-technical.json'),JSON.stringify(evidence,null,2)+'\n');}
 console.log(JSON.stringify({status:evidence.status,technical:evidence.technical}));
})();
