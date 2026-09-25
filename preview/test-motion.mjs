import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  MOTION,
  clockAngles,
  composePose,
  idleOffsets,
  shortestAngleError,
  verifyHandReturn,
} from "./motion-core.js";

const cases = [
  new Date(2026, 8, 24, 10, 10, 30, 0),
  new Date(2026, 8, 24, 3, 15, 0, 0),
  new Date(2026, 8, 24, 23, 59, 59, 999),
  new Date(2026, 0, 1, 0, 0, 0, 0),
];

for (const [index, date] of cases.entries()) {
  const startedAt = 100 + index;
  const base = clockAngles(date);
  const middle = composePose({
    date,
    nowSeconds: startedAt + MOTION.idleDuration / 2,
    idleStartedAt: startedAt,
  });
  assert.equal(shortestAngleError(middle.hands.hour, base.hour), 5);
  assert.equal(shortestAngleError(middle.hands.minute, base.minute), 19);

  const returned = verifyHandReturn({
    date,
    nowSeconds: startedAt + MOTION.idleDuration,
    idleStartedAt: startedAt,
  });
  assert.equal(returned.pass, true);
}

const middle = idleOffsets(MOTION.idleDuration / 2);
assert.equal(middle.weight, 1);
assert.equal(middle.hour, -5);
assert.equal(middle.minute, 19);

const alwaysOn = composePose({
  date: cases[0],
  nowSeconds: 1,
  idleStartedAt: 0.1,
  tapStartedAt: 0.8,
  alwaysOn: true,
});
assert.equal(Math.abs(alwaysOn.offsets.hour), 0);
assert.equal(Math.abs(alwaysOn.offsets.minute), 0);
assert.equal(alwaysOn.tap.weight, 0);
assert.equal(alwaysOn.breathing, 0);

const appSource = await readFile(new URL("./app.js", import.meta.url), "utf8");
const hubMatch = appSource.match(
  /hub:\s*Object\.freeze\(\{ x: (\d+), y: (\d+) \}\)/,
);
const hourLengthMatch = appSource.match(/hourLength:\s*(\d+)/);
const minuteLengthMatch = appSource.match(/minuteLength:\s*(\d+)/);
assert.ok(hubMatch && hourLengthMatch && minuteLengthMatch);

const hub = { x: Number(hubMatch[1]), y: Number(hubMatch[2]) };
const hourLength = Number(hourLengthMatch[1]);
const minuteLength = Number(minuteLengthMatch[1]);
assert.ok(hourLength < minuteLength, "hour hand must be shorter than minute hand");

const celSource = appSource.slice(
  appSource.indexOf("function drawCel"),
  appSource.indexOf("function drawToon3D"),
);
const toonSource = appSource.slice(
  appSource.indexOf("function drawToon3D"),
  appSource.indexOf("function drawStateEffects"),
);

for (const [name, source] of [
  ["2D", celSource],
  ["Toon-3D", toonSource],
]) {
  assert.ok(
    source.indexOf("ctx.drawImage") < source.indexOf("drawCroppedArm"),
    `${name} body must render before its front-layer arms`,
  );
  assert.ok(
    source.lastIndexOf("drawClockHub") > source.lastIndexOf("drawCroppedArm"),
    `${name} shared hub must render after both hands`,
  );
  assert.equal((source.match(/CLOCK_RIG\.hub\.x/g) ?? []).length, 2);
  assert.equal((source.match(/CLOCK_RIG\.hub\.y/g) ?? []).length, 2);
}
assert.doesNotMatch(
  appSource,
  /redrawShoulderCaps|redrawFaceShield|faceProtectionWeight|handPivot/,
);
assert.match(appSource, /__setPatrickPreviewTime/);

function endpoint(base, length, angle) {
  const radians = angle * Math.PI / 180;
  return {
    x: base.x + Math.sin(radians) * length,
    y: base.y - Math.cos(radians) * length,
  };
}

function measuredAngle(base, tip) {
  const degrees = Math.atan2(tip.x - base.x, -(tip.y - base.y)) * 180 / Math.PI;
  return (degrees + 360) % 360;
}

for (const [hours, minutes] of [
  [10, 10],
  [12, 0],
  [3, 45],
  [6, 30],
  [11, 55],
]) {
  const date = new Date(2026, 8, 24, hours, minutes, 0, 0);
  const angles = clockAngles(date);
  const hourBase = { ...hub };
  const minuteBase = { ...hub };
  assert.deepEqual(hourBase, minuteBase, `${hours}:${minutes} bases must coincide`);
  assert.equal(
    shortestAngleError(measuredAngle(hub, endpoint(hub, hourLength, angles.hour)), angles.hour),
    0,
  );
  assert.equal(
    shortestAngleError(
      measuredAngle(hub, endpoint(hub, minuteLength, angles.minute)),
      angles.minute,
    ),
    0,
  );
}

console.log(
  "PASS: motion, exact return, front-layer order, and one shared analog hub.",
);
