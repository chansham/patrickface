// Browser-only inspection evidence. Original PNGs and source pixels are untouched.
const {chromium}=require(process.env.PLAYWRIGHT_PACKAGE||'playwright');
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..'),out=path.join(root,'output/playwright/20261007-completion');
const address=process.env.PREVIEW_URL||'http://127.0.0.1:8765/';
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1100}});
  for(const[left,right]of[['chef-repair-20261006','chef-cookie-repair-20261007'],['focus-followup-20261006','focus-transition-repair-20261007'],['charging','charging-cozy-20261007']]){
   await page.goto(address+`size-review/?review=candidates&left=${left}&right=${right}`);await page.waitForFunction(()=>__patrickSizeReview?.status==='ready');
   await page.locator('#guides').uncheck();await page.locator('#landmarks').check();
   await page.locator('#compare-grid').screenshot({path:path.join(out,right+'-prior-candidate-measured-first.png')});
   for(const side of [0,1]){const slider=page.locator('#frame-'+side);await slider.fill(await slider.getAttribute('max'));await slider.dispatchEvent('input');}
   await page.locator('#compare-grid').screenshot({path:path.join(out,right+'-prior-candidate-measured-last.png')});
  }
  await page.setViewportSize({width:1400,height:820});
  await page.evaluate(async()=>{
   const {loadClip,frameGeometry}=await import('/size-review/render-core.js?v=20261006-size5');
   const repo=new URL('/',location.href),catalog=await(await fetch('/animation/candidates.json')).json(),layouts=await(await fetch('/experience/layouts.json')).json();
   const raw=catalog.clips.find(c=>c.id==='charging-cozy-20261007'),v1qc=await(await fetch('/animation/production-20261007-completion/charging-cozy-v1-qc.json')).json();
   const before={...raw,atlas:v1qc.source.path,sha256:v1qc.source.sha256,scale:1.25,anchorNormalized:v1qc.canvas.anchorNormalized,frameRegions:{...v1qc.regions,version:1}};
   const loaded=await Promise.all([before,raw].map(c=>loadClip(c,repo,new Map())));
   document.body.replaceChildren();document.body.style.cssText='margin:20px;background:#18151e;color:#fff;font:16px system-ui';
   const title=document.createElement('h1');title.textContent='充電 v1 → v2 · 相同來源像素倍率，沒有逐格 fit';document.body.append(title);
   for(let j=0;j<2;j++){const label=document.createElement('h2');label.textContent=j?'v2 選為待審：第7、9格增加過渡':'v1 中間稿：保留原圖作對照';document.body.append(label);
    const grid=document.createElement('div');grid.style.cssText='display:flex;gap:14px';document.body.append(grid);
    for(const i of [0,6,7,8,9,11]){const box=document.createElement('article'),canvas=document.createElement('canvas'),text=document.createElement('div');canvas.width=832;canvas.height=992;canvas.style.cssText='width:200px;background:#070609;border-radius:28px';const g=frameGeometry(loaded[j],i,catalog.master,layouts.layouts[0]);const ctx=canvas.getContext('2d');ctx.drawImage(g.source,...g.rect);text.textContent='第'+(i+1)+'格';box.append(canvas,text);grid.append(box);}
   }
  });
  await page.screenshot({path:path.join(out,'charging-v1-v2-fixed-scale.png'),fullPage:true});
  await page.setViewportSize({width:1250,height:950});
  await page.evaluate(async()=>{
   document.body.replaceChildren();document.body.style.cssText='margin:20px;background:#7c747e;color:#fff;font:16px system-ui';
   const heading=document.createElement('h1');heading.textContent='原始透明圖集：正確 alpha 黑／白底檢視（原檔不改）';document.body.append(heading);
   const image=await createImageBitmap(await(await fetch('/animation/charging-cozy-v2/atlas-generated.png')).blob());
   for(const color of ['#000','#fff']){const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;canvas.style.cssText='width:580px;margin:6px;vertical-align:top';const ctx=canvas.getContext('2d');ctx.fillStyle=color;ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,0,0);document.body.append(canvas);}
   image.close();
  });
  await page.screenshot({path:path.join(out,'charging-source-alpha-black-white.png'),fullPage:true});
  console.log('Captured prior-candidate semantic calipers and correct-alpha charging comparison.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
