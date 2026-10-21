import test from 'node:test';
import assert from 'node:assert/strict';
import { feedbackTarget, feedbackKey, feedbackRecord, sameFeedbackSource } from './frame-feedback.mjs';
const clip={id:'bath',title:'泡澡',version:2,catalogKind:'catalog',sha256:'a'.repeat(64),frameRegions:{sha256:'b'.repeat(64)},atlas:'animation/bath.png',scale:1.3,frameIndices:[0,1,2,3,5,6,7]};
const layout={id:'activity',title:'運動資訊',characterTransform:[.86,58.24,32]};
const target=()=>feedbackTarget(clip,4,layout,[.5,.97],200);
test('feedback binds the actual source frame across skipped atlas frames',()=>{const t=target();assert.equal(t.playbackFrame,4);assert.equal(t.sourceFrame,5);assert.equal(t.playbackFrameNumber,5);assert.equal(t.sourceFrameNumber,6);assert.equal(t.schemaVersion,1);assert.equal(t.frameNumbering,'zero-based');assert.equal(t.sourceSha256,clip.sha256);assert.equal(t.artApproval,false);});
test('identity separates new pixels, aliases, versions, layouts, scale and repeated frame positions',()=>{
 const t=target(),key=feedbackKey(t);
 for(const changed of [{...t,clipVersion:3},{...t,clipID:'bath-alias'},{...t,sourceSha256:'c'.repeat(64)},{...t,regionsSha256:'d'.repeat(64)},{...t,catalog:'candidates'},{...t,sourceFrame:4},{...t,playbackFrame:3},{...t,viewportWidth:300},{...t,layoutID:'classic'},{...t,rendering:{...t.rendering,scale:1.4}},{...t,rendering:{...t.rendering,layout:{...layout,characterTransform:[.56,8,354]}}}])assert.notEqual(feedbackKey(changed),key);
 assert.equal(feedbackKey(JSON.parse(JSON.stringify(t))),key);
});
test('records preserve creation time and use copied source/render snapshots',()=>{
 const t=target(),first=feedbackRecord(t,['eyes','outfit','eyes','unknown'],'偏紫',null,'first');
 const second=feedbackRecord(t,['eyes'],'修正說明',first,'second');t.rendering.layout.characterTransform[0]=0;
 assert.equal(first.rendering.layout.characterTransform[0],.86);assert.deepEqual(first.issueTypes,['eyes','outfit']);assert.equal(second.createdAt,'first');assert.equal(second.updatedAt,'second');assert.equal(second.artApproval,false);
});
test('same atlas path is insufficient to load old feedback onto a new source',()=>{assert.ok(sameFeedbackSource(target(),clip));assert.equal(sameFeedbackSource(target(),{...clip,sha256:'e'.repeat(64)}),false);assert.equal(sameFeedbackSource(target(),{...clip,version:3}),false);assert.equal(sameFeedbackSource(target(),null),false);});
test('an unknown playback frame cannot produce a misleading annotation',()=>assert.throws(()=>feedbackTarget(clip,99,layout,[.5,.97],200)));
