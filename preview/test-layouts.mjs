import assert from 'node:assert/strict';
import fs from 'node:fs';
import { validateLayouts, layoutID, transformRect } from './layout-core.js';
import { restoreExperience } from './experience-core.js';
import { createClockRig } from './clock-rig.js';
const layouts = validateLayouts(JSON.parse(fs.readFileSync(new URL('../experience/layouts.json', import.meta.url))));
assert.equal(layoutID(undefined), 'classic'); assert.equal(layoutID('future-version'), 'classic');
assert.equal(restoreExperience({ version: 1, settings: { sound: true } }).settings.layoutID, 'classic');
for (const layout of layouts) {
  assert.equal(restoreExperience({ version: 1, settings: { layoutID: layout.id } }).settings.layoutID, layout.id);
  const [scale, x, y] = layout.characterTransform;
  assert.deepEqual(transformRect([10, 20, 100, 200], layout), [10 * scale + x, 20 * scale + y, 100 * scale, 200 * scale]);
  // All source rectangles have the exact same multiplier, whatever frame bounds do.
  const small = transformRect([0, 0, 1, 1], layout), large = transformRect([0, 0, 500, 500], layout);
  assert.ok(Math.abs(large[2] / small[2] - 500) < 1e-9);
}
const manifest = JSON.parse(fs.readFileSync(new URL('../experience/clock/manifest.json', import.meta.url)));
const rig = createClockRig(manifest, [0, 1, 2].map(index => ({ index })));
for (const layout of layouts) {
  const stack = []; let matrix = [1, 0, 0, 1, 0, 0]; const tips = [];
  const context = { save() { stack.push([...matrix]); }, restore() { matrix = stack.pop(); }, fillRect() {},
    translate(x, y) { matrix[4] += matrix[0] * x + matrix[2] * y; matrix[5] += matrix[1] * x + matrix[3] * y; },
    scale(x, y) { matrix[0] *= x; matrix[1] *= x; matrix[2] *= y; matrix[3] *= y; },
    rotate(angle) { const [a,b,c,d] = matrix, s = Math.sin(angle), k = Math.cos(angle); matrix[0] = a*k+c*s;matrix[1]=b*k+d*s;matrix[2]=c*k-a*s;matrix[3]=d*k-b*s; },
    drawImage(frame, x, y) { const hand = manifest.hands.find(value => value.regionIndex === frame.index); if (hand) tips.push([hand.id,
      matrix[0]*(hand.tipPixels[0]+x)+matrix[2]*(hand.tipPixels[1]+y)+matrix[4],matrix[1]*(hand.tipPixels[0]+x)+matrix[3]*(hand.tipPixels[1]+y)+matrix[5]]); } };
  const angles = rig.draw([context], new Date(2026,0,1,10,10), layout.characterTransform), [scale,x,y] = layout.characterTransform;
  assert.equal(stack.length, 0, 'no leaking canvas transforms');
  for (const [id, tipX, tipY] of tips) {
    const hand = manifest.hands.find(value => value.id === id);
    assert.ok(Math.abs(tipX - ((manifest.layout.pivot[0] + Math.sin(angles[id])*hand.displayLength)*scale+x)) < 1e-7);
    assert.ok(Math.abs(tipY - ((manifest.layout.pivot[1] - Math.cos(angles[id])*hand.displayLength)*scale+y)) < 1e-7);
  }
}
console.log('PASS 4 shared layouts, legacy/unknown settings fallback, whole-clip geometry and actual-time hand tips.');
