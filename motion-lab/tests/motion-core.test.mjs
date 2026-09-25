import assert from "node:assert/strict";
import {
  MOTION,
  clockAngles,
  composePose,
  frameIndex,
  idleOffsets,
  performanceTier,
  shortestAngleError,
  verifyHandReturn,
} from "../motion-core.js";

const cases = [
  new Date(2026, 8, 23, 10, 10, 30, 0),
  new Date(2026, 8, 23, 3, 15, 0, 0),
  new Date(2026, 8, 23, 23, 59, 59, 999),
  new Date(2026, 0, 1, 0, 0, 0, 0),
];

for (const [index, date] of cases.entries()) {
  const start = 50 + index;
  const atStart = composePose({ date, nowSeconds: start, idleStartedAt: start });
  const atEnd = composePose({
    date,
    nowSeconds: start + MOTION.idleDuration,
    idleStartedAt: start,
  });
  const afterEnd = composePose({
    date,
    nowSeconds: start + MOTION.idleDuration + 10,
    idleStartedAt: start,
  });
  const target = clockAngles(date);

  assert.equal(shortestAngleError(atStart.hands.hour, target.hour), 0);
  assert.equal(shortestAngleError(atStart.hands.minute, target.minute), 0);
  assert.equal(shortestAngleError(atEnd.hands.hour, target.hour), 0);
  assert.equal(shortestAngleError(atEnd.hands.minute, target.minute), 0);
  assert.equal(shortestAngleError(afterEnd.hands.hour, target.hour), 0);
  assert.equal(shortestAngleError(afterEnd.hands.minute, target.minute), 0);

  const result = verifyHandReturn({
    date,
    nowSeconds: start + MOTION.idleDuration,
    idleStartedAt: start,
  });
  assert.equal(result.pass, true);
}

const midClip = idleOffsets(MOTION.idleDuration / 2);
assert.equal(midClip.weight, 1);
assert.equal(midClip.minute, 19);
assert.equal(midClip.hour, -5);

const tenTenThirty = clockAngles(new Date(2026, 8, 23, 10, 10, 30, 0));
assert.equal(tenTenThirty.minute, 63);
assert.equal(tenTenThirty.hour, 305.25);

assert.deepEqual(performanceTier({}), { name: "active", fps: 30, animated: true });
assert.deepEqual(performanceTier({ alwaysOn: true }), { name: "always-on", fps: 1, animated: false });
assert.deepEqual(performanceTier({ alwaysOn: true, lowPower: true }), { name: "low-power", fps: 0.2, animated: false });

const safetyPose = composePose({
  date: cases[0],
  nowSeconds: 5,
  idleStartedAt: 4.1,
  tapStartedAt: 4.8,
  lowPower: true,
});
assert.equal(safetyPose.offsets.minute, 0);
assert.equal(safetyPose.tap.weight, 0);
assert.equal(safetyPose.breathing, 0);

assert.equal(frameIndex(0, 10, 6), 0);
assert.equal(frameIndex(0.1, 10, 6), 1);
assert.equal(frameIndex(0.6, 10, 6), 0);
assert.equal(frameIndex(-1, 10, 6), -1);

console.log(`PASS: ${cases.length} clock cases; exact hand return; performance tiers; 6-frame loop.`);
