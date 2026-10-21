import { frameAt } from '../preview/player-core.js?v=20261006-layouts1';
import { validateLayouts, drawLayoutInformation } from '../preview/layout-core.js?v=20261012-activity1';
import { resource,decodeJSON,loadClip,frameGeometry,renderMemoryStats } from './render-core.js?v=20261008-acceptance2';
import { METRICS,measuredFootPoints,summarizeEvidence } from './acceptance-core.mjs?v=20261008-acceptance1';
import { FRAME_REVIEW_KEY, ISSUE_TYPES, feedbackTarget, feedbackKey, feedbackRecord, sameFeedbackSource } from './frame-feedback.mjs?v=20261012-feedback1';
const $=selector=>document.querySelector(selector),repo=new URL('../',import.meta.url);
const auditPath='animation/production-20261006-scale/body-scale-audit.json',repairAuditPath='animation/production-20261006-repair/body-scale-audit.json',followupAuditPath='animation/production-20261006-followup/body-scale-audit.json',completionAuditPath='animation/production-20261007-completion/body-scale-audit.json',landmarkAuditPath='animation/production-20261012-landmarks/body-scale-audit.json',raincoatAuditPath='animation/production-20261012-raincoat/body-scale-audit.json',storageKey='patrick.size-review.v1';
const params=new URLSearchParams(location.search),candidateMode=params.get('review')==='candidates';
const wardrobeAuditPath='animation/production-20261012-wardrobe/body-scale-audit.json';
const fitnessAuditPath='animation/production-20261012-fitness/body-scale-audit.json';
const playfulAuditPath='animation/production-20261012-playful/body-scale-audit.json';
const motionAuditPath='animation/production-20261012-motion/body-scale-audit.json';
const inbetweensAuditPath='animation/production-20261012-inbetweens/body-scale-audit.json';
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
const state={tab:'overview',playing:false,raf:null,started:0,head:360,body:650,guides:true,bounds:false,landmarks:false,pair:[{id:'pet',index:0},{id:'exercise',index:0}],layoutClip:'pet',layoutFrame:0,calibrationClip:null,calibrationFrame:0};
window.__patrickSizeReview={status:'loading',state};
let clips=[],candidateClips=[],layouts=[],catalog,outfits=[],audit=null,auditReports=[],notes={},beforeCatalog=null,calibrationClips=[];
let frameNotes={},selectedFrame=null;
const pendingFrameChanges=new Map();
const evidenceCache=new WeakMap();
try{const value=JSON.parse(localStorage.getItem(storageKey));if(value?.version===1&&value.notes&&typeof value.notes==='object')notes=value.notes;}catch{}
try{const value=JSON.parse(localStorage.getItem(FRAME_REVIEW_KEY));if(value?.version===1&&value.notes&&typeof value.notes==='object'&&!Array.isArray(value.notes))frameNotes=value.notes;}catch{}
const element=(tag,className,text)=>{const node=document.createElement(tag);if(className)node.className=className;if(text!==undefined)node.textContent=text;return node;};
const clipByID=id=>clips.find(clip=>clip.id===id);
const renderIdentity=clip=>({sourceSha256:clip.sha256,regionsSha256:clip.frameRegions.sha256,scale:clip.scale,masterAnchor:catalog.master.anchorNormalized,catalog:clip.catalogKind||'catalog'});
const noteKey=clip=>`${clip.catalogKind==='candidates'?'candidate:':''}${clip.id}:${clip.version}:${clip.sha256}:${clip.frameRegions.sha256}:${clip.scale}`;
function fillOptions(select){
  const groups=candidateMode?['catalog','candidates']:['catalog'];
  for(const kind of groups){const available=clips.filter(clip=>clip.catalogKind===kind);if(!available.length)continue;
    const parent=candidateMode?element('optgroup'):select;if(candidateMode){parent.label=kind==='catalog'?'目前日常':'待審改稿';select.append(parent);}
    for(const clip of available){const option=element('option','',clip.title);option.value=clip.id;parent.append(option);}
  }
}
function canvasView(parent,clip,index,layout,size='small'){
  const wrap=element('div','viewport'),canvas=element('canvas',`watch-canvas ${size}`);canvas.width=832;canvas.height=992;canvas.dataset.clip=clip.id;canvas.dataset.frame=index;canvas.dataset.layout=layout.id;
  const mark=element('button','mark-frame','標記這一格');mark.type='button';mark.addEventListener('click',()=>markFrame(canvas));
  canvas.setAttribute('aria-label',`${clip.title}第${index+1}格，同尺規${layout.title}`);wrap.append(canvas,element('div','viewport-label',size==='large'?'放大檢視 · 固定舞台':'200 px 同尺規'),mark);parent.append(wrap);return canvas;
}
function draw(canvas,clip,index,layout,masterAnchor=catalog.master.anchorNormalized){
  const ctx=canvas.getContext('2d'),geometry=frameGeometry(clip,index,{...catalog.master,anchorNormalized:masterAnchor},layout);
  ctx.clearRect(0,0,832,992);ctx.fillStyle='#070609';ctx.fillRect(0,0,832,992);ctx.drawImage(geometry.source,0,0,geometry.source.width,geometry.source.height,...geometry.rect);
  ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillStyle='#faf6fb';ctx.font=`${layout.id==='bold'?600:480} ${layout.timeFontSize}px "Segoe UI", sans-serif`;ctx.fillText('10:10',...layout.timeCenter);
  ctx.fillStyle='#ab99b5';ctx.font=`${layout.dateFontSize}px "Microsoft JhengHei", sans-serif`;ctx.fillText('10/6（週二）',...layout.dateCenter);
  drawLayoutInformation(ctx,layout);
  if(state.bounds){ctx.save();ctx.strokeStyle='#f3c68d';ctx.lineWidth=2;ctx.setLineDash([9,8]);ctx.strokeRect(...geometry.bounds);ctx.restore();}
  canvas.dataset.footLine='';
  if(state.landmarks){
    const measure=sourceMeasurement(clip,geometry.sourceIndex);
    if(measure){const [dx,dy]=clip.metadata.frames[geometry.sourceIndex].translation;
      const point=value=>[geometry.rect[0]+(value[0]+dx)*geometry.pixelScale,geometry.rect[1]+(value[1]+dy)*geometry.pixelScale];
      for(const [key,color]of [['faceCaliperPoints','#ff92c2'],['eyeLowerRimPoints','#8ae0ff']]){
        const points=validPoints(measure[key])?measure[key].map(point):null;if(!points)continue;ctx.save();ctx.strokeStyle=color;ctx.fillStyle=color;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(...points[0]);ctx.lineTo(...points[1]);ctx.stroke();for(const p of points){ctx.beginPath();ctx.arc(...p,4,0,Math.PI*2);ctx.fill();}ctx.restore();
      }
      const footPoints=measuredFootPoints(measure);
      if(footPoints){const endpoints=footPoints.map(point);ctx.save();ctx.strokeStyle='#a8dfba';ctx.setLineDash([6,6]);ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(...endpoints[0]);ctx.lineTo(...endpoints[1]);ctx.stroke();ctx.restore();canvas.dataset.footLine=JSON.stringify(endpoints);}
    }
  }
  if(state.guides){
    const[s,tx,ty]=layout.characterTransform;
    for(const [label,y,color]of[['頭',state.head*s+ty,'#e9b7d4'],['身',state.body*s+ty,'#8ccbe8'],['底',geometry.anchor[1],'#a8dfba']]){
      ctx.save();ctx.strokeStyle=color;ctx.fillStyle=color;ctx.lineWidth=2;ctx.setLineDash([7,8]);ctx.globalAlpha=.65;ctx.beginPath();ctx.moveTo(40,y);ctx.lineTo(792,y);ctx.stroke();ctx.globalAlpha=1;ctx.font='26px "Microsoft JhengHei",sans-serif';ctx.textAlign='left';ctx.fillText(label,45,y-17);ctx.restore();
    }
    ctx.save();ctx.strokeStyle='#b79ac077';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(geometry.anchor[0],230);ctx.lineTo(geometry.anchor[0],940);ctx.stroke();ctx.restore();
  }
  canvas.dataset.frame=String(index);canvas.dataset.sourceFrame=String(geometry.sourceIndex);canvas.dataset.clip=clip.id;canvas.dataset.layout=layout.id;
  canvas.dataset.pixelScale=String(geometry.pixelScale);canvas.dataset.anchor=JSON.stringify(geometry.anchor);canvas.dataset.rect=JSON.stringify(geometry.rect);
  canvas.reviewTarget=feedbackTarget(clip,index,layout,masterAnchor,canvas.getBoundingClientRect().width);
}
const validPoint=value=>Array.isArray(value)&&value.length===2&&value.every(Number.isFinite);
const validPoints=value=>Array.isArray(value)&&value.length===2&&value.every(validPoint);
function auditEntry(clip){
  const matches=auditReports.filter(report=>report.path===auditPath||clip.catalogKind==='candidates').flatMap(report=>(report.data?.clips||[]).filter(value=>value&&value.id===clip.id&&value.catalog===(clip.catalogKind||'catalog')).map(entry=>({entry,report})));
  const exact=matches.find(({entry})=>entry.sourceSha256===clip.sha256&&entry.regionsSha256===clip.frameRegions.sha256);
  if(exact)return{...exact,stale:false,scaleChanged:Number.isFinite(exact.entry.calibration?.currentScale)&&exact.entry.calibration.currentScale!==clip.scale};
  return{entry:null,report:matches[0]?.report||null,stale:matches.length>0,scaleChanged:false};
}
function sourceAudit(clip){return auditEntry(clip).entry;}
function evidence(clip){if(!evidenceCache.has(clip)){const{entry,report}=auditEntry(clip);evidenceCache.set(clip,summarizeEvidence(clip,entry,clip.metadata.frames.length,report?.data));}return evidenceCache.get(clip);}
function sourceMeasurement(clip,index){if(!evidence(clip).evidenceComplete)return null;const frames=sourceAudit(clip)?.frames;return Array.isArray(frames)?frames.find(frame=>frame.sourceFrame===index)?.source:null;}
function evidenceCard(clip){
  const value=evidence(clip),box=element('section',`evidence-coverage ${value.evidenceComplete?'complete':'blocked'}`);box.dataset.complete=String(value.evidenceComplete);
  box.append(element('strong','',value.evidenceComplete?`原始 ${value.sourceFrameCount} 格均有量測或未知紀錄`:'量測資料尚未通過完整性核對'));
  if(!value.evidenceComplete){box.append(element('p','',value.errors.map(error=>error.message).slice(0,3).join(' ')));return box;}
  for(const[key,label]of Object.entries(METRICS)){const metric=value.metrics[key],row=element('div','coverage-row');
    row.append(element('span','',`${label} ${metric.measured}/${value.sourceFrameCount} 格可量`));
    row.append(element('small','',metric.deltaPercent===null?'首末差異：未知':`末格比首格${Math.abs(metric.deltaPercent)<.05?'接近':`${metric.deltaPercent>0?'大':'小'} ${Math.abs(metric.deltaPercent).toFixed(1)}%`}`));box.append(row);
  }
  box.append(element('small','',`${value.sourceFrameCount-value.measuredFrames} 格沒有可靠人體尺規。閉眼與遮擋保留未知；姿勢變化仍須實看。`));
  if(value.reportedIssues.length){const issues=element('ul','known-art-issues');for(const issue of value.reportedIssues)issues.append(element('li','',typeof issue==='string'?issue:issue.message||issue.code));box.append(element('strong','', '原稿已知問題（不受百分比門檻影響）'),issues);}
  const review=value.warnings.filter(warning=>warning.code==='within-clip-variation');if(review.length)box.append(element('p','coverage-warning',review.map(warning=>warning.message).join(' ')));
  return box;
}
function visibleMetrics(clip,index){const measure=sourceMeasurement(clip,clip.frameIndices[index]),factor=frameGeometry(clip,index,catalog.master,layouts[0]).pixelScale*200/832;
  return Object.fromEntries(['faceWidth','eyeSeparation','eyeToFoot'].map(key=>[key,Number.isFinite(measure?.[key])&&measure[key]>=0&&(key!=='eyeToFoot'||measuredFootPoints(measure))?measure[key]*factor:null]));}
function describeMetrics(value,prefix=''){
  const result=[];if(!value||typeof value!=='object')return result;
  for(const[key,item]of Object.entries(value)){
    if(item===null)result.push(`${prefix}${key}：未知`);
    else if(typeof item==='number')result.push(`${prefix}${key}：${Number(item.toFixed(3))}`);
    else if(typeof item==='string'||typeof item==='boolean')result.push(`${prefix}${key}：${String(item)}`);
    else if(Array.isArray(item)&&item.length<=4&&item.every(x=>typeof x==='number'))result.push(`${prefix}${key}：${item.map(x=>Number(x.toFixed(2))).join(' / ')}`);
    else if(!Array.isArray(item))result.push(...describeMetrics(item,`${prefix}${key}.`));
  }return result;
}
function facts(card,clip,index,reference={id:'yawn',index:0}){
  const geometry=frameGeometry(clip,index,catalog.master,layouts[0]),node=card.querySelector('.facts');node.replaceChildren();
  node.append(element('div','clip-origin',clip.catalogKind==='candidates'?'待審改稿 · 尚未換入日常':'目前日常版本'),element('div','',`第 ${index+1}/${clip.frameCount} 格`));
  if(clip.catalogKind==='candidates'&&clip.description)node.append(element('p','candidate-description',clip.description));
  const metric=visibleMetrics(clip,index),referenceClip=clipByID(reference.id)||clip,ref=visibleMetrics(referenceClip,reference.index),isReference=clip.id===referenceClip.id&&index===reference.index;
  const measurement=element('div','body-measurements');
  for(const [key,label]of [['faceWidth','臉部大小'],['eyeSeparation','兩眼下緣間距'],['eyeToFoot','眼線至腳底']]){
    const value=metric[key],other=ref[key],row=element('div','measurement-row');row.append(element('span','',label));
    row.append(element('strong','',value===null?'未能量測':`${value.toFixed(1)} px`));
    if(value!==null&&other>0&&!isReference){const delta=(value/other-1)*100;row.append(element('small','',Math.abs(delta)<.5?'與參考接近':`比參考${delta>0?'大':'小'} ${Math.abs(delta).toFixed(0)}%`));}
    measurement.append(row);
  }node.append(measurement,element('small','',`200 px 內容舞台 · ${isReference?'此格作參考':`參考：${referenceClip.title}第${reference.index+1}格`}`),element('small','', '眼線至腳底受坐姿影響；遮擋的身體寬度不猜測。'));
  node.append(evidenceCard(clip));
  const details=element('details');details.append(element('summary','', '查看來源與量測細節'));details.append(element('small','',`來源第 ${geometry.sourceIndex+1} 格 · 主預覽整段倍率 ${clip.scale.toFixed(6)}`),element('small','',`1 source px → ${geometry.pixelScale.toFixed(4)} stage px；可見輪廓 ${geometry.bounds[2].toFixed(1)} × ${geometry.bounds[3].toFixed(1)} stage px（含衣帽與道具）`),element('small','',`PNG ${clip.sha256}`),element('small','',`輪廓 ${clip.frameRegions.sha256}`));
  const{entry,report,stale,scaleChanged}=auditEntry(clip);
  node.append(element('small','measurement-source',stale?'量測版本不符，本圖未套用。':entry?`量測來源：${report.label}`:'尚未有對應本圖的獨立量測。'));
  details.append(element('small','',stale?'圖片或輪廓 SHA 不同，數字與尺線均未套用。':!entry?'臉部／軀幹量測尚未提供。':`量測來源格：${(entry.referenceFrame??0)+1}；以下數值保留原量測欄位及單位。`));
  if(report){const link=element('a','',`${report.label} · 查看原資料 ↗`);link.href=new URL(report.path,repo);details.append(link);}
  if(scaleChanged)details.append(element('small','', '畫面數值按目前整段倍率重新換算；以下報告保留原本倍率的數字。'));
  if(entry)for(const line of describeMetrics(entry.measurements))details.append(element('small','',line));node.append(details);
  const flags=card.querySelector('.flags');flags.replaceChildren();
  if(stale)flags.append(element('li','', '量測版本已過期，需重新核對。'));
  if(entry?.flags?.length)for(const flag of entry.flags){let message=typeof flag==='string'?flag:flag.message||flag.code;if(Array.isArray(flag.frameIndices)&&flag.frameIndices.length){const ids=flag.frameIndices;message+=`（來源第 ${ids.slice(0,10).map(i=>i+1).join('、')}${ids.length>10?'…':''} 格${ids.every(i=>!clip.frameIndices.includes(i))?'；主預覽未啟用這些格':''}）`;}flags.append(element('li','',message));}
  else flags.append(element('li','',entry?'暫無自動旗標；仍需眼看頭身比例與動作變形。':'待補獨立頭身量測，不代表大小一致。'));
}
const overviewIndex=clip=>$('#overview-frame').value==='last'?clip.frameCount-1:$('#overview-frame').value==='middle'?Math.floor((clip.frameCount-1)/2):0;
function updateOverview(){for(const card of document.querySelectorAll('#outfit-grid .card')){const clip=clipByID(card.dataset.clip),index=overviewIndex(clip);draw(card.querySelector('canvas'),clip,index,layouts[0]);facts(card,clip,index);}}
function buildOverview(){for(const outfit of outfits){const clip=clipByID(outfit.clipId);if(!clip)continue;const card=element('article','card');card.dataset.clip=clip.id;card.append(element('h3','',outfit.title),element('small','',clip.title));canvasView(card,clip,0,layouts[0]);card.append(element('div','facts'),element('ul','flags'));const button=element('button','', '放到右邊比較 ↗');button.addEventListener('click',()=>{state.pair[1]={id:clip.id,index:0};syncCompare();switchTab('compare');});card.append(button);$('#outfit-grid').append(card);}updateOverview();}
function buildCompare(){for(let side=0;side<2;side++){
  const card=element('article','card comparison-card');card.dataset.side=String(side);const select=element('select');select.id=`compare-${side}`;select.setAttribute('aria-label',side===0?'左邊參考動作':'右邊比較動作');fillOptions(select);
  const control=element('label','frame-control','畫格');const slider=element('input');slider.type='range';slider.min=0;slider.step=1;slider.id=`frame-${side}`;const count=element('output');count.id=`frame-value-${side}`;control.append(slider,count);
  const pair=element('div','compare-viewports'),clip=clipByID(state.pair[side].id);canvasView(pair,clip,0,layouts[0],'large');canvasView(pair,clip,0,layouts[0]);card.append(element('h3','',side===0?'左邊 · 參考':'右邊 · 比較'),select,control,pair,element('div','facts'),element('ul','flags'));$('#compare-grid').append(card);
  select.addEventListener('change',()=>{stop();state.pair[side]={id:select.value,index:0};syncCompare();});slider.addEventListener('input',()=>{stop();state.pair[side].index=Number(slider.value);syncCompare();});
}syncCompare();}
function syncCompare(){for(let side=0;side<2;side++){const value=state.pair[side],clip=clipByID(value.id),card=$(`[data-side="${side}"]`);const key=JSON.stringify([value,state.pair[0],state.head,state.body,state.guides,state.bounds,state.landmarks]);if(card.dataset.renderKey===key)continue;card.dataset.renderKey=key;$(`#compare-${side}`).value=clip.id;const slider=$(`#frame-${side}`);slider.max=clip.frameCount-1;slider.value=value.index;$(`#frame-value-${side}`).textContent=`${value.index+1}/${clip.frameCount}`;for(const canvas of card.querySelectorAll('canvas'))draw(canvas,clip,value.index,layouts[0]);facts(card,clip,value.index,state.pair[0]);}}
function buildLayouts(){fillOptions($('#layout-clip'));for(const layout of layouts){const card=element('article','card');card.dataset.layout=layout.id;card.append(element('h3','',layout.title),element('small','',layout.description));const viewports=element('div','compare-viewports'),clip=clipByID(state.layoutClip);canvasView(viewports,clip,0,layout,'large');canvasView(viewports,clip,0,layout);card.append(viewports);$('#layout-grid').append(card);}syncLayouts();}
function syncLayouts(){const clip=clipByID(state.layoutClip);$('#layout-clip').value=clip.id;$('#layout-frame').max=clip.frameCount-1;$('#layout-frame').value=state.layoutFrame;$('#layout-frame-value').textContent=`${state.layoutFrame+1}/${clip.frameCount}`;for(const card of document.querySelectorAll('#layout-grid .card'))for(const canvas of card.querySelectorAll('canvas'))draw(canvas,clip,state.layoutFrame,layouts.find(layout=>layout.id===card.dataset.layout));}
function buildCalibration(){
  calibrationClips=clips.filter(clip=>{if(clip.catalogKind!=='catalog')return false;const old=beforeCatalog?.clips?.find(item=>item.id===clip.id);return old&&old.sha256===clip.sha256&&old.frameRegions?.sha256===clip.frameRegions.sha256&&Number.isFinite(old.scale)&&old.scale>0&&old.scale!==clip.scale;});
  if(!calibrationClips.length){$('#calibration-status').textContent='目前沒有可核對的倍率修正快照。原圖或輪廓版本不同時，不會假裝只是改了大小。';$('#calibration-clip').disabled=true;$('#calibration-frame').disabled=true;return;}
  for(const clip of calibrationClips){const option=element('option','',clip.title);option.value=clip.id;$('#calibration-clip').append(option);}state.calibrationClip=calibrationClips[0].id;
  for(const version of ['previous','current']){const card=element('article','card');card.dataset.calibrationVersion=version;card.append(element('h3','',version==='previous'?'校準前':'目前'),element('small','calibration-scale'));const viewports=element('div','compare-viewports'),clip=calibrationClips[0];canvasView(viewports,clip,0,layouts[0],'large');canvasView(viewports,clip,0,layouts[0]);card.append(viewports);$('#calibration-grid').append(card);}syncCalibration();
}
function syncCalibration(){
  const current=clipByID(state.calibrationClip);if(!current)return;const old=beforeCatalog.clips.find(clip=>clip.id===current.id),previous={...current,scale:old.scale};
  $('#calibration-clip').value=current.id;$('#calibration-frame').max=current.frameCount-1;$('#calibration-frame').value=state.calibrationFrame;$('#calibration-frame-value').textContent=`${state.calibrationFrame+1}/${current.frameCount}`;
  $('#calibration-status').textContent=`整段倍率 ×${(current.scale/old.scale).toFixed(2)}。兩側是同一張原圖、同一輪廓、同一格及同一落位基線，只改整段固定倍率。`;
  for(const version of ['previous','current']){const clip=version==='previous'?previous:current,card=$(`[data-calibration-version="${version}"]`);card.querySelector('.calibration-scale').textContent=`目錄倍率 ${clip.scale.toFixed(6)} · ${version==='previous'?'讀取校準前快照':'目前主預覽'}`;for(const canvas of card.querySelectorAll('canvas'))draw(canvas,clip,state.calibrationFrame,layouts[0]);}
  const entry=auditEntry(current).entry,notes=entry?.calibration?.residualWarnings||entry?.flags?.map(value=>typeof value==='string'?value:value.message)||[];
  $('#calibration-warnings').textContent=`${entry?.calibration?.reason||'這次只作有限尺寸校準，沒有改變原畫頭身比例。'} ${notes.join(' ')} 不能因此判定所有造型已一致。`;
}
function redraw(){if(state.tab==='overview')updateOverview();if(state.tab==='compare')syncCompare();if(state.tab==='layouts')syncLayouts();if(state.tab==='calibration')syncCalibration();}
function switchTab(tab){stop();state.tab=tab;document.querySelectorAll('[data-tab]').forEach(node=>node.setAttribute('aria-selected',String(node.dataset.tab===tab)));document.querySelectorAll('[data-panel]').forEach(node=>node.hidden=node.dataset.panel!==tab);redraw();}
function stop(){cancelAnimationFrame(state.raf);state.raf=null;state.playing=false;$('#stop-pair').disabled=true;$('#play-pair').disabled=reduced.matches;}
function play(){if(reduced.matches||document.hidden)return;stop();state.playing=true;state.started=performance.now();$('#stop-pair').disabled=false;$('#play-pair').disabled=true;state.pair.forEach(value=>value.index=0);syncCompare();
  const tick=now=>{if(!state.playing)return;const elapsed=now-state.started;let running=false;for(const value of state.pair){const clip=clipByID(value.id);value.index=frameAt(clip,elapsed);if(elapsed<clip.totalMs)running=true;}syncCompare();if(running)state.raf=requestAnimationFrame(tick);else stop();};state.raf=requestAnimationFrame(tick);
}
function loadNote(){const clip=clipByID($('#note-clip').value),note=notes[noteKey(clip)];$('#note-verdict').value=note?.verdict||'pending';$('#note').value=note?.text||'';}
function saveNote(){const clip=clipByID($('#note-clip').value);notes[noteKey(clip)]={clipID:clip.id,clipVersion:clip.version,catalog:clip.catalogKind||'catalog',rendering:renderIdentity(clip),verdict:$('#note-verdict').value,text:$('#note').value.slice(0,4000),updatedAt:new Date().toISOString(),artApproval:false};try{localStorage.setItem(storageKey,JSON.stringify({version:1,notes}));$('#save-state').textContent='尺寸意見已保存在本機。';}catch{$('#save-state').textContent='目前不能保存，請匯出意見留存。';}}

function fillFrameForm(){
  const note=frameNotes[feedbackKey(selectedFrame)];
  $('#frame-note').value=note?.text||'';
  for(const box of document.querySelectorAll('[name=frame-issue]'))box.checked=note?.issueTypes?.includes(box.value)||false;
  $('#frame-target').textContent=`${selectedFrame.clipTitle} · 播放第${selectedFrame.playbackFrame+1}格／來源第${selectedFrame.sourceFrame+1}格 · ${selectedFrame.rendering.layout.title} · ${selectedFrame.viewportWidth}px檢視`;
  $('#frame-target-detail').textContent=`${selectedFrame.catalog==='candidates'?'待審改稿':'日常版本'} · ${selectedFrame.clipID} · 版本 ${selectedFrame.clipVersion} · PNG ${selectedFrame.sourceSha256} · 輪廓 ${selectedFrame.regionsSha256} · 整段倍率 ${selectedFrame.rendering.scale}`;
  $('#frame-editor').hidden=false;$('#frame-remove').disabled=!note;
  $('#frame-save-state').textContent=note?'已讀取這一格的既有標記。':'選問題種類或寫下描述，會自動保存在本機。';
}
function markFrame(canvas){
  stop();selectedFrame=structuredClone(canvas.reviewTarget);selectedFrame.viewportWidth=Math.round(canvas.getBoundingClientRect().width);
  const target=$('#marked-frame');target.width=832;target.height=992;target.getContext('2d').drawImage(canvas,0,0);
  $('#frame-preview-unavailable').hidden=true;target.hidden=false;fillFrameForm();
  $('#frame-review').scrollIntoView({block:'start',behavior:'instant'});$('#frame-issues input').focus({preventScroll:true});
}
function latestFrameNotes(){
  const raw=localStorage.getItem(FRAME_REVIEW_KEY);if(raw===null)return{};
  const stored=JSON.parse(raw);
  if(stored?.version!==1||!stored.notes||typeof stored.notes!=='object'||Array.isArray(stored.notes))throw new Error('逐格意見格式不同');
  return stored.notes;
}
function applyPendingFrameChanges(base){
  const next={...base};for(const[key,record]of pendingFrameChanges){if(record)next[key]=record;else delete next[key];}return next;
}
function refreshFrameNotes(){
  try{frameNotes=applyPendingFrameChanges(latestFrameNotes());}
  catch{$('#frame-save-state').textContent='目前不能讀取本機意見；這一頁的標記仍可匯出。';}
  renderFrameNotes();
}
function persistFrameNotes(key,record){
  // The latest stored collection is authoritative, including deletions in another
  // tab. Only failed writes remain pending; stale in-memory records are not merged.
  pendingFrameChanges.set(key,record);
  frameNotes=applyPendingFrameChanges(frameNotes);
  try{frameNotes=applyPendingFrameChanges(latestFrameNotes());localStorage.setItem(FRAME_REVIEW_KEY,JSON.stringify({version:1,notes:frameNotes}));pendingFrameChanges.clear();$('#frame-save-state').textContent='這一格的問題已保存在本機。';}
  catch{$('#frame-save-state').textContent='目前不能保存；意見仍在此頁，請匯出留存。';}
  renderFrameNotes();
}
function saveFrameNote(){
  if(!selectedFrame)return;
  const issues=[...document.querySelectorAll('[name=frame-issue]:checked')].map(box=>box.value),text=$('#frame-note').value;
  if(!issues.length&&!text.trim()&&!frameNotes[feedbackKey(selectedFrame)])return;
  const key=feedbackKey(selectedFrame),record=feedbackRecord(selectedFrame,issues,text,frameNotes[key]);
  persistFrameNotes(key,record);$('#frame-remove').disabled=false;
}
function openFrameNote(note){
  stop();selectedFrame=structuredClone(note);const clip=clipByID(note.clipID),canvas=$('#marked-frame');
  const canDraw=sameFeedbackSource(note,clip)&&clip.frameIndices[note.playbackFrame]===note.sourceFrame;
  canvas.hidden=!canDraw;$('#frame-preview-unavailable').hidden=canDraw;
  if(canDraw){draw(canvas,{...clip,scale:note.rendering.scale},note.playbackFrame,note.rendering.layout,note.rendering.masterAnchor);}
  fillFrameForm();$('#frame-review').scrollIntoView({block:'start',behavior:'instant'});
}
function renderFrameNotes(){
  const list=$('#frame-notes');list.replaceChildren();const entries=Object.values(frameNotes);
  $('#frame-count').textContent=`已標記 ${entries.length} 則；舊版本與未載入的圖稿仍保留在匯出。`;
  for(const note of entries.sort((a,b)=>String(b.updatedAt).localeCompare(String(a.updatedAt)))){
    const row=element('li');
    if(!note?.rendering?.layout||!Number.isInteger(note.sourceFrame)){row.textContent='無法顯示的既有紀錄，匯出時仍保留。';list.append(row);continue;}
    row.append(element('strong','',`${note.clipTitle||note.clipID} · 播放第${note.playbackFrame+1}格／來源第${note.sourceFrame+1}格 · ${note.rendering.layout.title} · ${note.viewportWidth}px`),element('span','',(note.issueTypes||[]).map(id=>ISSUE_TYPES[id]||id).join('、')||'未分類'),element('p','',note.text||'（只標記問題種類）'));
    if(!sameFeedbackSource(note,clipByID(note.clipID)))row.append(element('small','', '舊版本或目前未載入；不套到新圖。'));
    else if(note.rendering.scale!==clipByID(note.clipID).scale||JSON.stringify(note.rendering.layout)!==JSON.stringify(layouts.find(value=>value.id===note.layoutID)))row.append(element('small','', '不同倍率或版式快照；仍保留原來的畫面與意見。'));
    const edit=element('button','','查看／修改');edit.type='button';edit.addEventListener('click',()=>openFrameNote(note));row.append(edit);list.append(row);
  }
}
function frameReviewExport(){refreshFrameNotes();if(pendingFrameChanges.size)$('#frame-save-state').textContent='已匯出，包含尚未存入本機的標記；請保留下載檔。';return Object.values(frameNotes);}

function chooseRevision(id){
  stop();const clip=clipByID(id);if(!clip||clip.catalogKind!=='candidates')return;
  const previous=clipByID(clip.comparisonClipId);
  if(previous&&previous.id!==clip.id)state.pair[0]={id:previous.id,index:0};
  state.pair[1]={id:clip.id,index:0};state.layoutClip=clip.id;state.layoutFrame=0;
  $('#revision-select').value=clip.id;
  $('#revision-status').textContent=previous?`原版本參考：${previous.title}；改稿：${clip.title}`:'這份候選尚未指定舊稿，可在左邊自行選擇比較對象。';
  $('#note-clip').value=clip.id;loadNote();switchTab('compare');
}
function configureRevisionReview(){
  if(!candidateMode)return;$('#revision-banner').hidden=false;$('#revision-entry').textContent='新舊改稿對照';
  const select=$('#revision-select');
  for(const clip of candidateClips){const option=element('option','',clip.title);option.value=clip.id;select.append(option);}
  select.disabled=!candidateClips.length;select.addEventListener('change',()=>chooseRevision(select.value));
  if(!candidateClips.length){$('#revision-status').textContent='目前沒有成功載入的待審畫稿；日常素材仍可比較。';return;}
  const requested=clipByID(params.get('right')),latest=candidateClips.filter(clip=>clipByID(clip.comparisonClipId)).at(-1)||candidateClips.at(-1);
  chooseRevision(requested?.catalogKind==='candidates'?requested.id:latest.id);
  const left=clipByID(params.get('left'));if(left){state.pair[0]={id:left.id,index:0};syncCompare();}
  if(params.has('right')&&requested?.catalogKind!=='candidates')$('#revision-status').textContent='指定的新稿尚未成功載入。目前顯示可用候選，請確認右側名稱。';
}

// Public links and review items use one-based SOURCE frames, never playback positions.
function selectSourceFrame({clipID,sourceFrame,sourceSha256}){
  const clip=clipByID(clipID);
  if(!candidateMode||clip?.catalogKind!=='candidates')throw new Error('這份待修畫稿未載入，沒有切換到其他版本。');
  if(!sourceSha256||clip.sha256!==sourceSha256)throw new Error('待修清單與目前原圖版本不同，沒有套用到新版。');
  if(!Number.isInteger(sourceFrame)||sourceFrame<1)throw new Error('來源格號無效，請重新選擇。');
  const index=clip.frameIndices.indexOf(sourceFrame-1);
  if(index<0)throw new Error('這個來源格不在目前播放版本中，沒有改成第一格。');
  chooseRevision(clip.id);state.pair[1].index=index;state.layoutFrame=index;syncCompare();
  return {clipID:clip.id,sourceFrame,playbackFrame:index+1,sourceSha256:clip.sha256};
}

async function loadKnownIssues(){
  if(!candidateMode)return;
  const section=$('#known-issues'),status=$('#known-issues-status'),list=$('#known-issues-list');section.hidden=false;
  const kinds={eyes:'眼睛／配色',motion:'動作／接續',outfit:'服裝／道具',scale:'大小／比例',crop:'裁剪／遮擋'};
  try{
    const report=decodeJSON(await resource('animation/production-20261012-review/art-priorities.json',repo));
    if(report.schemaVersion!==1||!Array.isArray(report.items))throw new Error('清單格式尚未就緒');
    const items=report.items.filter(item=>item&&typeof item.title==='string'&&Array.isArray(item.sourceFrames));
    const render=()=>{
      list.replaceChildren();const filter=$('#known-issues-kind').value,visible=items.filter(item=>filter==='all'||item.issueType===filter);
      for(const item of visible){
        const row=element('li'),clip=clipByID(item.clipID),matches=clip?.catalogKind==='candidates'&&clip.sha256===item.sourceSha256;
        row.dataset.clip=item.clipID;row.dataset.kind=item.issueType;
        row.append(element('strong','',`${clip?.title||item.clipID} · ${item.title}`));
        row.append(element('small','',`${kinds[item.issueType]||'待覆核'} · ${item.subjective?'偏好待確認':item.severity==='high'?'優先處理':'待修'}`));
        row.append(element('p','',item.detail||''));
        const links=element('div','issue-frame-links');
        for(const sourceFrame of [...new Set(item.sourceFrames)]){
          const available=matches&&Number.isInteger(sourceFrame)&&clip.frameIndices.includes(sourceFrame-1);
          const button=element('button','',`看來源第 ${sourceFrame} 格`);button.type='button';button.disabled=!available;button.dataset.sourceFrame=sourceFrame;
          button.addEventListener('click',()=>{
            try{selectSourceFrame({clipID:item.clipID,sourceFrame,sourceSha256:item.sourceSha256});status.textContent=`已定位來源第 ${sourceFrame} 格。查看後可在圖片下標記，你的意見保持原樣。`;$('#compare-grid').scrollIntoView({block:'start',behavior:reduced.matches?'auto':'smooth'});}
            catch(error){status.textContent=error.message;}
          });links.append(button);
        }
        row.append(links);if(!matches)row.append(element('small','issue-stale','原圖版本不同或尚未載入；保留問題文字，定位已停用。'));list.append(row);
      }
      status.textContent=`顯示 ${visible.length} 項；共 ${items.length} 項已發現問題。清單由製作檢查整理，不代表其他畫格已全部合格。`;
      $('#known-issues-title').textContent=`已知待修清單 · ${items.length} 項`;
    };
    $('#known-issues-kind').addEventListener('change',render);render();
    section.open=params.get('issues')==='1';
  }catch(error){status.textContent=`待修清單暫時無法載入（${error.message}）；逐格比較與你的意見仍可使用。`;}
  if(params.has('sourceFrame')){
    try{selectSourceFrame({clipID:params.get('right'),sourceFrame:Number(params.get('sourceFrame')),sourceSha256:params.get('sourceSha256')});}
    catch(error){status.textContent=error.message;section.open=true;}
  }
}

async function loadAudit(){
  const definitions=[{path:auditPath,label:'舊版量測快照',selector:'#audit-source'}];
  if(candidateMode)definitions.unshift({path:raincoatAuditPath,label:'10/12 雨衣兩姿態尺規',selector:'#raincoat-audit-source'},{path:landmarkAuditPath,label:'10/12運動與充電逐格人體量測',selector:'#landmark-audit-source'},{path:completionAuditPath,label:'10/7改稿量測',selector:'#completion-audit-source'},{path:followupAuditPath,label:'追加改稿量測',selector:'#followup-audit-source'},{path:repairAuditPath,label:'首輪改稿量測',selector:'#repair-audit-source'});
  if(candidateMode)definitions.unshift({path:wardrobeAuditPath,label:'10/12 雨衣修訂與運動毛巾尺規',selector:'#wardrobe-audit-source'});
  if(candidateMode)definitions.unshift({path:fitnessAuditPath,label:'10/12 健身服裝與動作尺規',selector:'#fitness-audit-source'});
  if(candidateMode)definitions.unshift({path:playfulAuditPath,label:'10/12 牛仔與抱枕睡衣尺規',selector:'#playful-audit-source'});
  if(candidateMode)definitions.unshift({path:motionAuditPath,label:'10/12 節奏比較 · 沿用同源量尺',selector:'#motion-audit-source'});
  if(candidateMode)definitions.unshift({path:inbetweensAuditPath,label:'10/12 抱枕與鞠躬新原畫尺規',selector:'#inbetweens-audit-source'});
  auditReports=await Promise.all(definitions.map(async definition=>{
    const node=$(definition.selector);node.hidden=false;
    try{const data=decodeJSON(await resource(definition.path,repo));if(data.schemaVersion!==1||!Array.isArray(data.clips))throw new Error('格式不支援');
      node.textContent=`${definition.label}：${definition.path} · ${data.generatedAt||'日期未提供'}。按圖片與輪廓版本核對。`;
      return{...definition,data};
    }catch(error){node.textContent=`${definition.label}未讀入，對應數字與尺線留空；其他量測及圖稿仍可查看。`;return{...definition,data:null,error:error.message};}
  }));
  audit=auditReports.find(report=>report.path===auditPath)?.data||null;
  Object.assign(window.__patrickSizeReview,{auditLoaded:Boolean(audit),auditSources:auditReports.map(({path,label,data,error})=>({path,label,loaded:Boolean(data),error}))});
}
async function start(){
  const [rawCatalog,rawThemes,rawLayouts]=await Promise.all(['animation/catalog.json','experience/themes.json','experience/layouts.json'].map(async path=>decodeJSON(await resource(path,repo))));catalog=rawCatalog;layouts=validateLayouts(rawLayouts);const cache=new Map(),failures=[];
  const inputs=catalog.clips.filter(clip=>clip.atlas).map(clip=>({...clip,catalogKind:'catalog'}));
  if(candidateMode){try{const candidates=decodeJSON(await resource('animation/candidates.json',repo));
    if(!candidates.reviewOnly||!Array.isArray(candidates.clips))throw new Error('待審目錄格式無效');
    if(JSON.stringify(candidates.master?.anchorNormalized)!==JSON.stringify(catalog.master?.anchorNormalized))throw new Error('待審與日常的落位基線不同，暫不能放進同尺規對照');
    const ids=new Set(inputs.map(clip=>clip.id));
    for(const clip of candidates.clips.filter(clip=>clip.atlas)){if(ids.has(clip.id)){failures.push({id:clip.id,error:'待審識別碼與其他版本重複'});continue;}ids.add(clip.id);inputs.push({...clip,catalogKind:'candidates'});}
  }catch(error){failures.push({id:'candidates',error:error.message});}}
  // Decode at most two source atlases concurrently; compose frame canvases only
  // when drawn. Keeping every full-size source frame used hundreds of MiB.
  const loaded=new Array(inputs.length);let nextInput=0;
  const loadNext=async()=>{while(nextInput<inputs.length){const index=nextInput++,clip=inputs[index];try{loaded[index]=await loadClip(clip,repo,cache);}catch(error){failures.push({id:clip.id,error:error.message});loaded[index]=null;}}};
  await Promise.all([loadNext(),loadNext()]);cache.clear();clips=loaded.filter(Boolean);candidateClips=clips.filter(clip=>clip.catalogKind==='candidates');if(!clips.some(clip=>clip.catalogKind==='catalog'))throw new Error('沒有可讀取的主預覽素材');
  outfits=rawThemes.outfits.filter(value=>clipByID(value.clipId));if(!clipByID(state.pair[0].id))state.pair[0].id=clips[0].id;if(!clipByID(state.pair[1].id))state.pair[1].id=clips.at(-1).id;state.layoutClip=state.pair[0].id;
  await loadAudit();try{beforeCatalog=decodeJSON(await resource('animation/production-20261006-scale/catalog-before.json',repo));}catch{}
  $('#summary').textContent=`${outfits.length} 套造型 · ${clips.filter(clip=>clip.catalogKind==='catalog').length} 段播放版本。以下全部固定為 200 px 視窗，沿用經典版同一舞台。`;
  buildOverview();buildCompare();buildLayouts();buildCalibration();fillOptions($('#note-clip'));loadNote();configureRevisionReview();renderFrameNotes();await loadKnownIssues();
  for(const button of document.querySelectorAll('[data-tab]'))button.addEventListener('click',()=>switchTab(button.dataset.tab));
  $('#overview-frame').addEventListener('change',updateOverview);$('#layout-clip').addEventListener('change',()=>{state.layoutClip=$('#layout-clip').value;state.layoutFrame=0;syncLayouts();});$('#layout-frame').addEventListener('input',()=>{state.layoutFrame=Number($('#layout-frame').value);syncLayouts();});
  $('#calibration-clip').addEventListener('change',()=>{state.calibrationClip=$('#calibration-clip').value;state.calibrationFrame=0;syncCalibration();});$('#calibration-frame').addEventListener('input',()=>{state.calibrationFrame=Number($('#calibration-frame').value);syncCalibration();});
  for(const id of ['head','body'])$(`#${id}-line`).addEventListener('input',()=>{state[id]=Number($(`#${id}-line`).value);$(`#${id}-value`).textContent=String(state[id]);redraw();});
  for(const id of ['guides','bounds','landmarks'])$(`#${id}`).addEventListener('change',()=>{state[id]=$(`#${id}`).checked;redraw();});$('#play-pair').addEventListener('click',play);$('#stop-pair').addEventListener('click',stop);reduced.addEventListener('change',stop);document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});stop();
  for(const box of document.querySelectorAll('[name=frame-issue]'))box.addEventListener('change',saveFrameNote);
  window.addEventListener('storage',event=>{if(event.key===FRAME_REVIEW_KEY||event.key===null)refreshFrameNotes();});
  $('#frame-note').addEventListener('input',saveFrameNote);$('#frame-save').addEventListener('click',saveFrameNote);
  $('#frame-remove').addEventListener('click',()=>{if(!selectedFrame)return;persistFrameNotes(feedbackKey(selectedFrame),null);fillFrameForm();$('#frame-save-state').textContent='已移除這一格的標記；其他意見保持。';});
  $('#note-clip').addEventListener('change',loadNote);$('#note').addEventListener('input',saveNote);$('#note-verdict').addEventListener('change',saveNote);$('#export').addEventListener('click',()=>{const value={schemaVersion:1,exportedAt:new Date().toISOString(),artApproval:false,notes:Object.values(notes),frameReviewSchemaVersion:1,frameNotes:frameReviewExport(),currentRendering:Object.fromEntries(clips.map(clip=>[clip.id,renderIdentity(clip)])),auditPath,auditGeneratedAt:audit?.generatedAt||null,auditSources:auditReports.map(({path,label,data})=>({path,label,loaded:Boolean(data),generatedAt:data?.generatedAt||null}))};const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));const link=element('a');link.href=url;link.download='patrick-size-review.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
  $('#loading').hidden=true;if(failures.length){$('#error').hidden=false;$('#error').textContent=`${failures.length}段載入失敗：${failures.map(value=>`${value.id}（${value.error}）`).join('、')}。其他素材仍可比較。`;}
  Object.assign(window.__patrickSizeReview,{status:'ready',candidateMode,candidateClipIDs:candidateClips.map(clip=>clip.id),clipIDs:clips.map(clip=>clip.id),outfitIDs:outfits.map(value=>value.id),failures,memory:renderMemoryStats,evidence:id=>{const clip=clipByID(id);return clip?evidence(clip):{clipID:id,evidenceComplete:false,artApproval:false,errors:[{code:'clip-not-loaded',message:'圖稿未成功載入；請查看頁面載入錯誤。'}]};},geometry:(id,index,layoutID)=>{const clip=clipByID(id);if(!clip)throw new Error(`圖稿未成功載入：${id}`);const geometry=frameGeometry(clip,index,catalog.master,layouts.find(value=>value.id===layoutID));return{rect:geometry.rect,anchor:geometry.anchor,pixelScale:geometry.pixelScale,bounds:geometry.bounds};}});
}
start().catch(error=>{stop();$('#error').hidden=false;$('#error').textContent=error.message;$('#loading').hidden=true;window.__patrickSizeReview.status='error';window.__patrickSizeReview.error=error.message;});
