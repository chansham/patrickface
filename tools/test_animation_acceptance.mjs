import test from 'node:test';
import assert from 'node:assert/strict';
import {summarizeEvidence,measuredFootPoints} from '../size-review/acceptance-core.mjs';
const copy=value=>structuredClone(value);
function fixture(){
  const clip={id:'review',catalogKind:'candidates',sha256:'a'.repeat(64),frameRegions:{sha256:'b'.repeat(64)},frameCount:3,frameIndices:[0,1,2],scale:1};
  const measure={faceWidth:100,eyeSeparation:30,eyeToFoot:180,faceCaliperPoints:[[0,20],[100,20]],eyeLowerRimPoints:[[35,20],[65,20]],eyeMidpoint:[50,20],eyeToFootPoints:[[50,20],[50,200]]};
  const entry={id:clip.id,catalog:'candidates',sourceSha256:clip.sha256,regionsSha256:clip.frameRegions.sha256,sourceFrameCount:3,
    frames:Array.from({length:3},(_,sourceFrame)=>({sourceFrame,source:copy(measure),flags:[]}))};
  return{clip,entry};
}
test('complete evidence remains unapproved and does not normalize measurements',()=>{
  const{clip,entry}=fixture(),before=copy(entry),result=summarizeEvidence(clip,entry,3);
  assert.equal(result.evidenceComplete,true);assert.equal(result.artApproval,false);assert.equal(result.reviewRequired,true);assert.deepEqual(entry,before);
});
test('missing or duplicate source frames block, including frames omitted from playback',()=>{
  const{clip,entry}=fixture();clip.frameCount=2;clip.frameIndices=[0,2];entry.frames.splice(1,1);
  assert.ok(summarizeEvidence(clip,entry,3).errors.some(e=>e.code==='missing-frame'));
  entry.frames.push(copy(entry.frames[0]));assert.ok(summarizeEvidence(clip,entry,3).errors.some(e=>e.code==='duplicate-frame'));
});
test('ID, catalog and both hashes must match exactly',()=>{
  for(const key of ['id','catalog','sourceSha256','regionsSha256']){const{clip,entry}=fixture();entry[key]='different';const result=summarizeEvidence(clip,entry,3);assert.equal(result.evidenceComplete,false);assert.deepEqual(result.metrics,{});}
});
test('closed eyes are explicit unknowns, never interpolated from another frame',()=>{
  const{clip,entry}=fixture();entry.frames[2]={sourceFrame:2,source:null,flags:[{message:'Closed eyes; no reliable landmarks'}]};
  const result=summarizeEvidence(clip,entry,3);assert.equal(result.evidenceComplete,true);assert.equal(result.metrics.faceWidth.measured,2);assert.equal(result.metrics.faceWidth.unknown,1);assert.equal(result.metrics.faceWidth.deltaPercent,null);
});
test('unexplained null does not count as completed evidence',()=>{
  const{clip,entry}=fixture();entry.frames[1].source.faceWidth=null;
  assert.ok(summarizeEvidence(clip,entry,3).errors.some(e=>e.code==='unexplained-unknown'));
});
test('real twenty percent endpoint shrink raises a review flag without changing art scale',()=>{
  const{clip,entry}=fixture();entry.frames[2].source.faceWidth=80;entry.frames[2].source.faceCaliperPoints=[[10,20],[90,20]];
  const result=summarizeEvidence(clip,entry,3);assert.ok(Math.abs(result.metrics.faceWidth.deltaPercent+20)<1e-10);assert.ok(result.warnings.some(w=>w.code==='endpoint-difference'));assert.equal(clip.scale,1);
});
test('double playback timing does not double the number of source measurements',()=>{
  const{clip,entry}=fixture();clip.frameCount=6;clip.frameIndices=[0,1,2,0,1,2];const result=summarizeEvidence(clip,entry,3);
  assert.equal(result.playbackFrameCount,6);assert.equal(result.uniqueUsedFrames,3);assert.equal(result.metrics.faceWidth.measured,3);
});
test('large props and transparent canvas bounds cannot replace unknown anatomy',()=>{
  const{clip,entry}=fixture();entry.frames=entry.frames.map(frame=>({...frame,source:null,bounds:[0,0,900,900],flags:[{message:'Body hidden behind prop'}]}));
  const result=summarizeEvidence(clip,entry,3);assert.equal(result.evidenceComplete,true);assert.equal(result.measuredFrames,0);assert.equal(result.metrics.faceWidth.first,null);assert.equal(result.metrics.eyeToFoot.last,null);
});
test('foot caliper follows measured feet, not contour anchor or cushion',()=>{
  const{clip,entry}=fixture();entry.frames[0].anchorSource=[50,235];assert.deepEqual(measuredFootPoints(entry.frames[0].source),[[50,20],[50,200]]);
  entry.frames[0].source.eyeToFootPoints[1][1]=235;assert.equal(measuredFootPoints(entry.frames[0].source),null);assert.ok(summarizeEvidence(clip,entry,3).errors.some(e=>e.code==='missing-landmark'));
});
test('legacy foot scalar reconstructs only its measured line',()=>{
  const{entry}=fixture();delete entry.frames[0].source.eyeToFootPoints;assert.deepEqual(measuredFootPoints(entry.frames[0].source),[[50,20],[50,200]]);
  entry.frames[0].source.eyeToFoot=null;assert.equal(measuredFootPoints(entry.frames[0].source),null);
});
test('negative/string/nonfinite values and out-of-range playback fail closed',()=>{
  for(const bad of [-2,'100',Infinity]){const{clip,entry}=fixture();entry.frames[1].source.faceWidth=bad;assert.equal(summarizeEvidence(clip,entry,3).evidenceComplete,false);}
  const{clip,entry}=fixture();clip.frameIndices[2]=3;assert.ok(summarizeEvidence(clip,entry,3).errors.some(e=>e.code==='playback-sequence'));
});
test('face and eye values must agree with their caliper distance',()=>{
  for(const key of ['faceWidth','eyeSeparation']){const{clip,entry}=fixture();entry.frames[1].source[key]*=.8;assert.ok(summarizeEvidence(clip,entry,3).errors.some(e=>e.code==='missing-landmark'));}
  const{clip,entry}=fixture();entry.frames[1].source.faceWidth=100.75;assert.equal(summarizeEvidence(clip,entry,3).evidenceComplete,true);
});
test('known five percent art defect survives below automated warning threshold',()=>{
  const{clip,entry}=fixture();entry.flags=[{code:'known-short-body',message:'原畫末段短身 5.2%，仍需重畫。'}];const result=summarizeEvidence(clip,entry,3);assert.deepEqual(result.reportedIssues,entry.flags);assert.equal(result.artApproval,false);
});
test('legacy source-level hidden-feet reason requires exact source and contour identity',()=>{
  const{clip,entry}=fixture();clip.atlas='chef.png';for(const frame of entry.frames)frame.source.eyeToFoot=null;
  const report={sources:[{sourcePath:clip.atlas,sourceSha256:clip.sha256,regionsSha256:clip.frameRegions.sha256,footBaselineUnavailableReason:'Opaque cushion, anatomical feet not measured'}]};
  const valid=summarizeEvidence(clip,entry,3,report);assert.equal(valid.evidenceComplete,true);assert.equal(valid.metrics.faceWidth.measured,3);assert.equal(valid.metrics.eyeToFoot.measured,0);
  report.sources[0].regionsSha256='changed';assert.equal(summarizeEvidence(clip,entry,3,report).evidenceComplete,false);
});
