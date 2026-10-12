// Assemble the source-pinned technical evidence and separately recorded visual findings.
// Does not rerun a browser, edit artwork, or mark any art approved.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),out='output/playwright/20261008-active-inspection/';
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p))),sha=p=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,p))).digest('hex');
const relative=p=>path.relative(root,p).replaceAll(path.sep,'/');
const t=read(relative(path.join(__dirname,'inspection-technical.json'))),gate=read(out+'evidence-gate.json');
if(t.status!=='fresh-technical-evidence-complete-manual-art-review-pending')throw Error('Fresh playback evidence incomplete');
const catalog=read('animation/candidates.json');
const findings={
 'running-first-20261006':[
  {kind:'original-art-transition',frames:[4,5,6,7,8,9,10],severity:'revision-required',finding:'第4→5、6→7、8→9、9→10格出現左右朝向直接切換；頭、肩、擺手與短褲花紋一起翻轉，沒有前向中間姿態。畫格完整，問題在原畫朝向接續。',novelty:'本輪擴充定位至6→7及9→10，不只重述先前4→5/8→9。'},
  {kind:'proportion-limit',frames:[1,16],severity:'review-required',finding:'本輪共同舞台首末可見站姿比坐姿高、臉較小；不能用整人高度強行等大。腿部抬落使總輪廓變動，並非可直接當成身體縮放。',novelty:'本輪重新實看同舞台；沒有新增人體量測。'},
  {kind:'ending',frames:[13,14,15,16],severity:'review-required',finding:'吐氣後半睜→全睜→半睜的收尾眼神在最後4格明顯切換；不是資料遺失或自動重播。'}],
 'exercise-repair-20261006':[
  {kind:'contact-shape',frames:[4,5,6,7],severity:'review-required',finding:'舉至臉前時，圓手、啞鈴把手與粗短腕部重疊，200px下手腕至上臂的彎曲關係不清楚。仍可辨認在舉啞鈴，但握持自然度不能只憑像素相接就通過。',novelty:'本輪重新定位到4–7格；未發現確切斷肢或輪廓工具bug。'},
  {kind:'expression-transition',frames:[5,6],severity:'review-required',finding:'用力皺眉在相鄰150ms格切成半睜放鬆，動作仍維持高舉。可讀成搞怪表情，但情緒節奏是否合意需使用者審，不當成確定破圖。'},
  {kind:'ending',frames:[13,14,16],severity:'review-required',finding:'吐氣格後直接回半睜；首末落位穩定，沒有重現舊整人上下跳動。全16格保留，並非跳過問題格。'}],
 'charging-cozy-20261007':[
  {kind:'original-art-transition',frames:[7,8,9,10],severity:'revision-required',finding:'靠枕第7→8格和回正第9→10格仍有可見角度階躍；已補的中間姿勢有效，但不能稱柔順過渡完成。'},
  {kind:'contact',frames:[3,4,5,6,8],severity:'review-required',finding:'本輪200px實播擷取能辨認手臂抬枕、擠壓與臉頰靠上抱枕；姿勢不是整張平移。壓縮時抱枕輪廓/閃電標記形變仍待美術審稿。'},
  {kind:'proportion-limit',frames:[1,12],severity:'review-required',finding:'首末臉部大小視覺接近，帽沿/下擺略有變形。拖鞋遮住真腳，不能把紫鞋底當眼足身高；本輪沒有補猜此尺規。'}]
};
const clips=t.clips.map(c=>{
 const current=catalog.clips.find(x=>x.id===c.id);if(current.sha256!==c.sourceSha256||current.frameRegions.sha256!==c.regionsSha256||current.scale!==c.scale)throw Error('Candidate changed since capture');
 if(sha(current.atlas)!==c.sourceSha256||sha(current.frameRegions.path)!==c.regionsSha256)throw Error('Source changed');
 const g=gate.clips.find(x=>x.clipID===c.id);if(!g||g.sourceSha256!==c.sourceSha256||g.regionsSha256!==c.regionsSha256)throw Error('Gate/source mismatch');
 const visuals=findings[c.id].map(f=>({...f,times:f.frames.map(i=>({sourceFrame:i,recordedElapsedMs:c.live.frames.find(x=>x.sourceFrame===i).elapsedMs})),image:c.frameSheet}));
 return{id:c.id,atlas:c.atlas,sourceSha256:c.sourceSha256,regionsSha256:c.regionsSha256,scale:c.scale,frameCount:c.frameCount,
  technical:{oneFixedScaleAndAnchor:true,allFramesDisplayed:true,stoppedAtLast:true,layoutFrames:c.frameCount*4,overlaps:0,outsideStage:0},
  visual:{inspectedSourceFrames:Array.from({length:c.frameCount},(_,i)=>i+1),method:'逐張看過本輪真實1×擷取contact sheet及时间；不聲稱观看了原生真機。',findings:visuals},
  semanticEvidence:{fromExistingShaPinnedAudit:g.auditPath,recomputedBodyMetricsThisRound:false,recordedFrames:g.recordedFrames,measuredFrames:g.measuredFrames,metrics:g.metrics},
  silhouetteHeightAt200CssPx:Object.fromEntries(c.layouts.map(l=>{const v=l.frames.map(f=>f.bounds[3]*200/832);return[l.id,{min:Math.min(...v),max:Math.max(...v),meaning:'整個強輪廓，包含衣帽道具；不是人體高度'}]})),artApproval:false};
});
const screenshotNames=[...t.clips.map(c=>path.basename(c.frameSheet)),'common-stage-first-200px.png','common-stage-last-200px.png',...['classic','bold','theater','activity'].map(id=>'common-stage-'+id+'-middle-200px.png')];
const report={schemaVersion:1,inspectedAt:'2026-10-08',finalizedAt:'2026-10-12',artApproval:false,allArtworkComplete:false,newArtworkCount:0,
 scope:{selection:'3個明確既有候選，不代表整個主素材庫',categories:['跑步','啞鈴','睡衣充電'],sourceFrames:44,sourcePNGsUnchanged:true,catalogUnchanged:true,regionsUnchanged:true},
 technical:{...t.technical,renderer:'正式size-review/render-core與preview/player-core.frameAt，單獨輕量頁只載入3套',scopeLimit:'未重新測主頁完整排程、Watch原生、手機同步或時計角度。',
  clockNote:'實際rAF與performance.now時鐘，無假時鐘。首個rAF timestamp可比請求前記時早約8ms，原始小負值保留；來源格順序、相鄰格時間差及停末格證據不受影響。'},
 visual:{actuallyInspectedFrames:44,actuallyInspectedScreenshots:screenshotNames.length,confirmedRendererBugFound:false,
  newObservation:'運動資訊版同200px舞台，整個角色輪廓只約69–86px高；時間/資料沒有相交，但手腕握持和眼神細節不如經典版可辨。需要區分無遮擋與動作可讀。',
  missingCoverage:['手臂時計本輪未實播或測角度','其他日常/候選素材本輪未逐格重驗','未做新的全身人體landmark量測','沒有iPhone/Watch真機視覺批准']},
 qualityGate:{path:out+'evidence-gate.json',sha256:sha(out+'evidence-gate.json'),evidenceComplete:gate.evidenceComplete,artApproval:false,
  measuredSourceFrames:clips.reduce((n,c)=>n+c.semanticEvidence.measuredFrames,0),explicitlyUnknownSourceFrames:clips.reduce((n,c)=>n+c.frameCount-c.semanticEvidence.measuredFrames,0),totalFrames:44,
  meaning:'每格有來源與明示未知，不代表44格都有可用人體數字。啞鈴0/16、跑步2/16、睡衣2/12可量，真眼足距全部未知。'},
 clips,evidence:{technicalReport:{path:relative(path.join(__dirname,'inspection-technical.json')),sha256:sha(relative(path.join(__dirname,'inspection-technical.json')))},screenshots:screenshotNames.map(n=>({path:out+n,sha256:sha(out+n)}))}};
fs.writeFileSync(path.join(__dirname,'inspection-report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({technical:report.technical,measured:report.qualityGate.measuredSourceFrames,unknown:report.qualityGate.explicitlyUnknownSourceFrames,screenshots:report.evidence.screenshots.length}));
