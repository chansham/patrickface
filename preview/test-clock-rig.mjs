import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createClockRig } from './clock-rig.js';
const manifest = JSON.parse(fs.readFileSync(new URL('../experience/clock/manifest.json', import.meta.url)));
const frames = [0, 1, 2].map(index => ({ index }));
const rig = createClockRig(manifest, frames);
function trace() {
  let matrix = [1, 0, 0, 1, 0, 0]; const stack = [], tips = [];
  return { tips, save() { stack.push([...matrix]); }, restore() { matrix = stack.pop(); }, fillRect() {},
    translate(x, y) { matrix[4] += matrix[0] * x + matrix[2] * y; matrix[5] += matrix[1] * x + matrix[3] * y; },
    scale(x, y) { matrix[0] *= x; matrix[1] *= x; matrix[2] *= y; matrix[3] *= y; },
    rotate(angle) { const [a, b, c, d] = matrix, s = Math.sin(angle), k = Math.cos(angle); matrix[0] = a * k + c * s; matrix[1] = b * k + d * s; matrix[2] = c * k - a * s; matrix[3] = d * k - b * s; },
    drawImage(image, x, y) { const hand = manifest.hands.find(item => item.regionIndex === image.index); if (!hand) return;
      const tipX = hand.tipPixels[0] + x, tipY = hand.tipPixels[1] + y;
      tips.push({ id: hand.id, x: matrix[0] * tipX + matrix[2] * tipY + matrix[4], y: matrix[1] * tipX + matrix[3] * tipY + matrix[5] }); }
  };
}
for (const [hour, minute, second] of [[0, 0, 0], [3, 30, 0], [6, 45, 20], [10, 10, 0]]) {
  const context = trace(), angles = rig.draw([context], new Date(2026, 0, 1, hour, minute, second));
  for (const tip of context.tips) {
    const hand = manifest.hands.find(item => item.id === tip.id), angle = angles[tip.id];
    assert.ok(Math.abs(tip.x - (manifest.layout.pivot[0] + Math.sin(angle) * hand.displayLength)) < 1e-8);
    assert.ok(Math.abs(tip.y - (manifest.layout.pivot[1] - Math.cos(angle) * hand.displayLength)) < 1e-8);
  }
}
const invalid = structuredClone(manifest); invalid.hands[0].lengthPixels = 0;
assert.throws(() => createClockRig(invalid, frames), /長度無效/);
console.log('PASS real hand-tip geometry at 00:00, 03:30, 06:45:20 and 10:10, per-hand direction correction, common pivot and length guards.');
