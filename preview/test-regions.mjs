import assert from 'node:assert/strict';
import { normalizeClip, validateFrameRegions, sourceRect, destinationRect, cleanReview } from './player-core.js';
const clip = normalizeClip({ id: 'contour', title: '輪廓測試', version: 1, atlas: 'animation/test.png', width: 20, height: 12,
  columns: 2, rows: 1, frameCount: 2, frameRegions: { path: 'regions.json', version: 1, sha256: 'b'.repeat(64) },
  sha256: 'a'.repeat(64), durationsMs: [100, 100] });
const metadata = { schemaVersion: 1, source: { path: clip.atlas, width: 20, height: 12, sha256: clip.sha256 },
  canvas: { width: 12, height: 12, anchorPixels: [6, 10], anchorNormalized: [0.5, 10/12] },
  frames: [
    { sourceBounds: [1,1,4,5], anchorSource: [3,6], translation: [3,4], placement: [4,5], rows: [[1,2,4],[2,1,5],[3,1,5],[4,1,5],[5,1,5]] },
    { sourceBounds: [11,2,6,5], anchorSource: [14,7], translation: [-8,3], placement: [3,5], rows: [[2,13,15],[3,12,16],[4,11,17],[5,11,17],[6,11,17]] },
  ] };
assert.equal(validateFrameRegions(clip,metadata),metadata);
clip.renderCanvas=metadata.canvas;
assert.deepEqual(sourceRect(clip,0),[0,0,12,12]);assert.deepEqual(sourceRect(clip,1),[0,0,12,12]);
assert.equal(destinationRect(clip)[2],destinationRect(clip)[3]);
for(const frame of metadata.frames){assert.deepEqual(frame.anchorSource.map((n,i)=>n+frame.translation[i]),[6,10]);}
const bad=fn=>{const m=structuredClone(metadata);fn(m);assert.throws(()=>validateFrameRegions(clip,m),/輪廓資料/);};
bad(m=>m.source.sha256='c'.repeat(64));bad(m=>m.source.path='animation/wrong.png');bad(m=>m.source.width=21);
bad(m=>m.frames[0].translation[0]+=.5);bad(m=>m.frames[0].placement[0]++);bad(m=>m.frames[0].anchorSource[1]++);
bad(m=>m.frames[0].rows[0]=[1,0,4]);bad(m=>m.frames[0].rows[0]=[1,2,4,3,5]);bad(m=>m.frames[0].rows.push(m.frames[0].rows[0]));
bad(m=>m.frames[0].rows=[]);bad(m=>m.frames[0].rows[0][2]=20);bad(m=>m.canvas.anchorPixels[1]--);bad(m=>m.frames.pop());
const preserved=cleanReview({version:1,sha256:clip.sha256,note:'old crop note',frames:{0:'revise'},rendering:{method:'older-method',revision:7}},clip);
assert.deepEqual(preserved.rendering,{method:'older-method',revision:7});assert.equal(preserved.sections.action.note,'old crop note');
console.log('PASS: source identity, integer translation, fixed common canvas/foot anchor, run bounds/non-overlap, unequal contour sizes without fitting, and historical review provenance.');
