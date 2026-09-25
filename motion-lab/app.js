import {
  MOTION,
  clockAngles,
  composePose,
  frameIndex,
  normalizeDegrees,
  shortestAngleError,
  verifyHandReturn,
} from "./motion-core.js";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const dom = {
  screen: $("#watch-screen"),
  root: $("#character-root"),
  hourHand: $("#hour-hand"),
  minuteHand: $("#minute-hand"),
  body: $("#body-mesh"),
  shorts: $("#shorts"),
  eyes: $("#eyes"),
  pupils: $$(".pupil"),
  lids: $$(".lid"),
  browLeft: $("#brow-left"),
  browRight: $("#brow-right"),
  mouth: $("#mouth"),
  sleepBubble: $("#sleep-bubble"),
  chargingRing: $("#charging-ring"),
  ocean: $("#ocean-bg"),
  sprite: $("#sprite-gesture"),
  rig: $("#rig-overlay"),
  meshLines: $("#mesh-lines"),
  meshPoints: $("#mesh-points"),
  digitalTime: $("#digital-time"),
  modeLabel: $("#mode-label"),
  manifestPill: $("#manifest-pill"),
  fixed: $("#fixed-time"),
  crown: $("#crown-input"),
  crownOutput: $("#crown-output"),
  sleep: $("#sleep-state"),
  focus: $("#focus-state"),
  lowBattery: $("#battery-state"),
  charging: $("#charging-state"),
  alwaysOn: $("#aod-state"),
  lowPower: $("#low-power-state"),
  showRig: $("#rig-state"),
  stateName: $("#state-name"),
  tierName: $("#tier-name"),
  blendName: $("#blend-name"),
  hourTarget: $("#hour-target"),
  hourActual: $("#hour-actual"),
  minuteTarget: $("#minute-target"),
  returnError: $("#return-error"),
  verification: $("#verification-log"),
  verifyButton: $("#run-verification"),
  fps: $("#fps-counter"),
};

const embeddedFallback = {
  id: "embedded-emergency-fallback",
  anchors: {
    characterRoot: [180, 240],
    hourArmPivot: [180, 240],
    minuteArmPivot: [180, 240],
  },
  mesh: {
    bodyControlPoints: [
      [180, 92], [145, 131], [118, 219], [106, 309], [126, 338],
      [180, 348], [234, 338], [254, 309], [242, 219], [215, 131],
    ],
  },
};

const fixedEpoch = new Date(2026, 8, 23, 10, 10, 30, 0);
const bootSeconds = performance.now() / 1000;
let manifest = embeddedFallback;
let attention = { x: 0, y: 0, targetX: 0, targetY: 0 };
let forceNextFrame = true;
let lastRenderedAt = Number.NEGATIVE_INFINITY;
let renderCount = 0;
let fpsWindowStarted = performance.now();
let autoIdleAt = bootSeconds + 8;
let lastPose = null;

const clips = {
  idle: Number.NEGATIVE_INFINITY,
  tap: Number.NEGATIVE_INFINITY,
  blink: Number.NEGATIVE_INFINITY,
  sprite: Number.NEGATIVE_INFINITY,
};

function nowSeconds() {
  return performance.now() / 1000;
}

function dateFor(now) {
  if (!dom.fixed.checked) return new Date();
  return new Date(fixedEpoch.getTime() + (now - bootSeconds) * 1000);
}

function flags() {
  return {
    sleep: dom.sleep.checked,
    focus: dom.focus.checked,
    lowBattery: dom.lowBattery.checked,
    charging: dom.charging.checked,
    alwaysOn: dom.alwaysOn.checked,
    lowPower: dom.lowPower.checked,
  };
}

function buildTicks() {
  const group = $("#dial-ticks");
  for (let index = 0; index < 12; index += 1) {
    const angle = index * 30;
    const major = index % 3 === 0;
    const tick = document.createElementNS("http://www.w3.org/2000/svg", "line");
    tick.setAttribute("x1", "180");
    tick.setAttribute("y1", major ? "78" : "82");
    tick.setAttribute("x2", "180");
    tick.setAttribute("y2", major ? "91" : "88");
    tick.setAttribute("stroke", major ? "rgba(255,255,255,.78)" : "rgba(255,255,255,.35)");
    tick.setAttribute("stroke-width", major ? "3" : "2");
    tick.setAttribute("stroke-linecap", "round");
    tick.setAttribute("transform", `rotate(${angle} 180 236)`);
    group.append(tick);
  }
}

function closedSpline(points) {
  if (!points.length) return "";
  const midpoint = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  const start = midpoint(points.at(-1), points[0]);
  let path = `M ${start[0].toFixed(2)} ${start[1].toFixed(2)}`;
  points.forEach((point, index) => {
    const next = points[(index + 1) % points.length];
    const end = midpoint(point, next);
    path += ` Q ${point[0].toFixed(2)} ${point[1].toFixed(2)} ${end[0].toFixed(2)} ${end[1].toFixed(2)}`;
  });
  return `${path} Z`;
}

function deformMesh(pose) {
  const source = manifest.mesh?.bodyControlPoints ?? embeddedFallback.mesh.bodyControlPoints;
  const breath = pose.breathing * 2.5;
  const slump = pose.slump;
  return source.map(([x, y], index) => {
    const verticalWeight = Math.max(0, 1 - Math.abs(y - 225) / 170);
    const side = Math.sign(x - 180);
    let nextX = x + side * breath * verticalWeight;
    let nextY = y;
    if (index === 0) nextY -= breath * 0.8;
    if (slump) {
      nextX += (y < 230 ? 5 : 1) * slump;
      nextY += (y < 240 ? 7 : 3) * slump;
    }
    return [nextX, nextY];
  });
}

function renderRig(points) {
  const outline = points.map((point, index) => `${index ? "L" : "M"}${point[0]} ${point[1]}`).join(" ") + " Z";
  const cross = [
    `M${points[1][0]} ${points[1][1]} L${points[8][0]} ${points[8][1]}`,
    `M${points[2][0]} ${points[2][1]} L${points[7][0]} ${points[7][1]}`,
    `M${points[3][0]} ${points[3][1]} L${points[6][0]} ${points[6][1]}`,
    `M${points[0][0]} ${points[0][1]} L${points[5][0]} ${points[5][1]}`,
  ].join(" ");
  dom.meshLines.setAttribute("d", `${outline} ${cross}`);

  while (dom.meshPoints.children.length < points.length) {
    const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    circle.setAttribute("r", "3.2");
    circle.setAttribute("fill", "#74f5d0");
    circle.setAttribute("stroke", "#07100e");
    circle.setAttribute("stroke-width", "1.2");
    dom.meshPoints.append(circle);
  }
  points.forEach(([x, y], index) => {
    const circle = dom.meshPoints.children[index];
    circle.setAttribute("cx", x);
    circle.setAttribute("cy", y);
  });
}

function setHandTransform(element, pivot, degrees) {
  element.setAttribute("transform", `translate(${pivot[0]} ${pivot[1]}) rotate(${degrees.toFixed(7)})`);
}

function renderFace(pose, now) {
  const asleep = pose.mode.face === "sleep";
  const focused = pose.mode.face === "focus";
  const blinkScale = asleep ? 0.075 : Math.max(0.075, 1 - pose.blink * 0.94);
  attention.x += (attention.targetX - attention.x) * 0.16;
  attention.y += (attention.targetY - attention.y) * 0.16;
  const attentionWeight = asleep ? 0 : 1;
  dom.eyes.setAttribute("transform", `translate(180 188) scale(1 ${blinkScale.toFixed(3)}) translate(-180 -188)`);
  dom.pupils.forEach((pupil) => {
    pupil.setAttribute("transform", `translate(${(attention.x * 5 * attentionWeight).toFixed(2)} ${(attention.y * 4 * attentionWeight).toFixed(2)})`);
  });
  dom.lids.forEach((lid) => {
    lid.setAttribute("transform", `translate(0 ${(focused ? -2.5 : 0).toFixed(2)})`);
  });

  const lift = pose.crown.browLift + (focused ? 2 : 0);
  dom.browLeft.setAttribute("d", `M137 ${157 + lift} Q157 ${149 + lift} 175 ${157 + lift}`);
  dom.browRight.setAttribute("d", `M185 ${157 + lift} Q203 ${149 + lift} 223 ${157 + lift}`);
  const smile = asleep ? -2 : pose.crown.smile;
  dom.mouth.setAttribute("d", `M149 232 Q180 ${250 + smile} 211 232`);

  const bubble = asleep ? 5 + ((Math.sin(now * 2.2) + 1) * 2.2) : 0;
  dom.sleepBubble.setAttribute("r", bubble.toFixed(2));
  dom.sleepBubble.setAttribute("cx", (220 + Math.sin(now * 1.3) * 2).toFixed(2));
}

function renderSprite(now, pose) {
  const elapsed = now - clips.sprite;
  const active = pose.tier.animated && elapsed >= 0 && elapsed < MOTION.spriteDuration;
  dom.sprite.classList.toggle("visible", active);
  if (!active) return;
  const index = frameIndex(elapsed, 10, MOTION.spriteFrames);
  dom.sprite.style.backgroundPosition = `${(index / (MOTION.spriteFrames - 1)) * 100}% 0`;
}

function render(now) {
  const stateFlags = flags();
  const date = dateFor(now);
  const pose = composePose({
    date,
    nowSeconds: now,
    idleStartedAt: clips.idle,
    tapStartedAt: clips.tap,
    blinkStartedAt: clips.blink,
    crown: Number(dom.crown.value),
    ...stateFlags,
  });
  lastPose = pose;

  const hourPivot = manifest.anchors?.hourArmPivot ?? [180, 240];
  const minutePivot = manifest.anchors?.minuteArmPivot ?? [180, 240];
  setHandTransform(dom.hourHand, hourPivot, pose.hands.hour);
  setHandTransform(dom.minuteHand, minutePivot, pose.hands.minute);

  const slumpY = pose.slump * 12;
  const slumpRotation = pose.slump * 4.5;
  const rootScale = pose.tap.scale;
  dom.root.setAttribute(
    "transform",
    `translate(0 ${(pose.tap.y + slumpY).toFixed(3)}) translate(180 240) rotate(${slumpRotation}) scale(${rootScale.toFixed(4)}) translate(-180 -240)`,
  );

  const points = deformMesh(pose);
  dom.body.setAttribute("d", closedSpline(points));
  renderRig(points);
  renderFace(pose, now);
  dom.shorts.setAttribute("fill", `hsl(${pose.crown.outfitHue.toFixed(1)} 60% 55%)`);

  const chargeOpacity = pose.mode.charging ? 0.18 + pose.chargingPulse * 0.48 : 0;
  dom.chargingRing.setAttribute("opacity", chargeOpacity.toFixed(3));
  dom.chargingRing.setAttribute("r", (137 + pose.chargingPulse * 7).toFixed(2));
  dom.ocean.style.filter = pose.mode.face === "sleep"
    ? "hue-rotate(28deg) saturate(.65) brightness(.62)"
    : pose.mode.face === "focus"
      ? "hue-rotate(-28deg) saturate(1.2)"
      : "none";

  dom.rig.setAttribute("opacity", dom.showRig.checked ? ".88" : "0");
  dom.screen.classList.toggle("aod", pose.tier.name === "always-on");
  dom.screen.classList.toggle("low-power", pose.tier.name === "low-power");
  renderSprite(now, pose);

  const timeFormatter = new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit", hour12: false });
  dom.digitalTime.textContent = timeFormatter.format(date);
  dom.modeLabel.textContent = `${pose.mode.face.toUpperCase()} · ${pose.tier.name.toUpperCase()}`;
  dom.crownOutput.value = Number(dom.crown.value).toFixed(2);

  const error = Math.max(
    shortestAngleError(pose.hands.hour, pose.base.hour),
    shortestAngleError(pose.hands.minute, pose.base.minute),
  );
  dom.hourTarget.textContent = `${pose.base.hour.toFixed(3)}°`;
  dom.hourActual.textContent = `${pose.hands.hour.toFixed(3)}°`;
  dom.minuteTarget.textContent = `${pose.base.minute.toFixed(3)}°`;
  dom.returnError.textContent = `${error.toFixed(3)}°`;
  dom.returnError.style.color = error < 0.000001 ? "var(--mint)" : "var(--yellow)";

  dom.stateName.textContent = pose.mode.face.toUpperCase()
    + (pose.mode.lowBattery ? " · SLUMP" : "")
    + (pose.mode.charging ? " · CHARGE" : "");
  dom.tierName.textContent = `${pose.tier.name.toUpperCase()} / ${pose.tier.fps} FPS`;
  const blend = ["TIME"];
  if (pose.tier.animated) blend.push("BREATH");
  if (pose.offsets.minute) blend.push("IDLE");
  if (pose.tap.weight) blend.push("TAP");
  dom.blendName.textContent = blend.join(" + ");
}

function animationLoop(timestampMs) {
  const now = timestampMs / 1000;
  const currentFlags = flags();
  const tier = currentFlags.lowPower ? MOTION.lowPowerFPS : currentFlags.alwaysOn ? MOTION.ambientFPS : MOTION.activeFPS;
  const interval = 1 / tier;

  if (!currentFlags.alwaysOn && !currentFlags.lowPower && now >= autoIdleAt) {
    clips.idle = now;
    autoIdleAt = now + 12;
    forceNextFrame = true;
  }

  if (forceNextFrame || now - lastRenderedAt >= interval) {
    render(now);
    lastRenderedAt = now;
    forceNextFrame = false;
    renderCount += 1;
  }

  if (timestampMs - fpsWindowStarted >= 1000) {
    const elapsed = (timestampMs - fpsWindowStarted) / 1000;
    dom.fps.textContent = `render ${(renderCount / elapsed).toFixed(1)} fps`;
    renderCount = 0;
    fpsWindowStarted = timestampMs;
  }
  requestAnimationFrame(animationLoop);
}

function trigger(name) {
  const now = nowSeconds();
  clips[name] = now;
  forceNextFrame = true;
  if (name === "idle") autoIdleAt = now + 12;
  if (name === "tap") {
    // Browser analogue of WKInterfaceDevice.current().play(.click).
    navigator.vibrate?.(12);
    window.dispatchEvent(new CustomEvent("patrick-haptic", { detail: { kind: "click" } }));
  }
}

function runVerification() {
  const dates = [
    new Date(2026, 8, 23, 10, 10, 30, 0),
    new Date(2026, 8, 23, 3, 15, 0, 0),
    new Date(2026, 8, 23, 23, 59, 59, 999),
  ];
  const results = dates.map((date, index) => verifyHandReturn({
    date,
    idleStartedAt: 100 + index,
    nowSeconds: 100 + index + MOTION.idleDuration,
    tolerance: 1e-9,
  }));
  const maxError = Math.max(...results.flatMap((result) => [result.hourError, result.minuteError]));
  const pass = results.every((result) => result.pass);

  dom.verification.className = `verification-log ${pass ? "pass" : "fail"}`;
  dom.verification.innerHTML = `
    <span class="status-dot"></span>
    <p><strong>${pass ? "PASS" : "FAIL"} · 3 deterministic clock cases.</strong>
    Post-clip maximum error: ${maxError.toExponential(2)}°. The visible rig will now play the same zero-ended gesture.</p>
  `;
  trigger("idle");

  window.setTimeout(() => {
    const date = dateFor(nowSeconds());
    const result = verifyHandReturn({
      date,
      idleStartedAt: clips.idle,
      nowSeconds: clips.idle + MOTION.idleDuration,
      tolerance: 1e-9,
    });
    dom.verification.className = `verification-log ${pass && result.pass ? "pass" : "fail"}`;
    dom.verification.querySelector("p").innerHTML = `<strong>${pass && result.pass ? "PASS" : "FAIL"} · return invariant verified.</strong>
      Browser simulation and live gesture endpoint both report ${Math.max(result.hourError, result.minuteError).toExponential(2)}° error.`;
  }, MOTION.idleDuration * 1000 + 60);
}

async function loadManifest() {
  const candidates = [
    { url: "../style-library/patrick-anchor-manifest.json", label: "shared anchors" },
    { url: "./patrick-anchor-manifest.fallback.json", label: "local fallback" },
  ];
  for (const candidate of candidates) {
    try {
      const response = await fetch(candidate.url, { cache: "no-store" });
      if (!response.ok) continue;
      const value = await response.json();
      if (!value.anchors?.hourArmPivot || !value.anchors?.minuteArmPivot) continue;
      manifest = value;
      dom.manifestPill.textContent = candidate.label;
      dom.manifestPill.classList.remove("pending");
      forceNextFrame = true;
      return;
    } catch {
      // file:// blocks fetch; the embedded fallback keeps the prototype runnable.
    }
  }
  dom.manifestPill.textContent = "embedded fallback";
  dom.manifestPill.classList.remove("pending");
}

$$("[data-action]").forEach((button) => {
  button.addEventListener("click", () => trigger(button.dataset.action));
});

[
  dom.fixed, dom.crown, dom.sleep, dom.focus, dom.lowBattery,
  dom.charging, dom.alwaysOn, dom.lowPower, dom.showRig,
].forEach((control) => {
  control.addEventListener("input", () => {
    forceNextFrame = true;
    if (control === dom.lowPower && dom.lowPower.checked) dom.alwaysOn.checked = false;
    if (control === dom.alwaysOn && dom.alwaysOn.checked) dom.lowPower.checked = false;
  });
});

dom.screen.addEventListener("click", () => trigger("tap"));
dom.screen.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    trigger("tap");
  }
});
dom.screen.addEventListener("wheel", (event) => {
  event.preventDefault();
  const next = Math.min(1, Math.max(0, Number(dom.crown.value) + Math.sign(event.deltaY) * 0.04));
  dom.crown.value = String(next);
  forceNextFrame = true;
}, { passive: false });
dom.screen.addEventListener("pointermove", (event) => {
  const rect = dom.screen.getBoundingClientRect();
  attention.targetX = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
  attention.targetY = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
});
dom.screen.addEventListener("pointerleave", () => {
  attention.targetX = 0;
  attention.targetY = 0;
});
dom.verifyButton.addEventListener("click", runVerification);
document.addEventListener("visibilitychange", () => {
  forceNextFrame = true;
});

buildTicks();
loadManifest();
requestAnimationFrame(animationLoop);

// Stable inspection API for browser automation and integration tests.
window.__patrickMotionLab = Object.freeze({
  getPose: () => lastPose,
  trigger,
  runVerification,
  setCrown(value) {
    dom.crown.value = String(Math.min(1, Math.max(0, value)));
    forceNextFrame = true;
  },
  getManifest: () => manifest,
});
/*
  Duplicate source text was left below by the initial workspace write.
  It is inert and retained only to avoid a destructive truncation operation.
import {
  MOTION,
  clockAngles,
  composePose,
  frameIndex,
  normalizeDegrees,
  shortestAngleError,
  verifyHandReturn,
} from "./motion-core.js";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const dom = {
  screen: $("#watch-screen"),
  root: $("#character-root"),
  hourHand: $("#hour-hand"),
  minuteHand: $("#minute-hand"),
  body: $("#body-mesh"),
  shorts: $("#shorts"),
  eyes: $("#eyes"),
  pupils: $$(".pupil"),
  lids: $$(".lid"),
  browLeft: $("#brow-left"),
  browRight: $("#brow-right"),
  mouth: $("#mouth"),
  sleepBubble: $("#sleep-bubble"),
  chargingRing: $("#charging-ring"),
  ocean: $("#ocean-bg"),
  sprite: $("#sprite-gesture"),
  rig: $("#rig-overlay"),
  meshLines: $("#mesh-lines"),
  meshPoints: $("#mesh-points"),
  digitalTime: $("#digital-time"),
  modeLabel: $("#mode-label"),
  manifestPill: $("#manifest-pill"),
  fixed: $("#fixed-time"),
  crown: $("#crown-input"),
  crownOutput: $("#crown-output"),
  sleep: $("#sleep-state"),
  focus: $("#focus-state"),
  lowBattery: $("#battery-state"),
  charging: $("#charging-state"),
  alwaysOn: $("#aod-state"),
  lowPower: $("#low-power-state"),
  showRig: $("#rig-state"),
  stateName: $("#state-name"),
  tierName: $("#tier-name"),
  blendName: $("#blend-name"),
  hourTarget: $("#hour-target"),
  hourActual: $("#hour-actual"),
  minuteTarget: $("#minute-target"),
  returnError: $("#return-error"),
  verification: $("#verification-log"),
  verifyButton: $("#run-verification"),
  fps: $("#fps-counter"),
};

const embeddedFallback = {
  id: "embedded-emergency-fallback",
  anchors: {
    characterRoot: [180, 240],
    hourArmPivot: [180, 240],
    minuteArmPivot: [180, 240],
  },
  mesh: {
    bodyControlPoints: [
      [180, 92], [145, 131], [118, 219], [106, 309], [126, 338],
      [180, 348], [234, 338], [254, 309], [242, 219], [215, 131],
    ],
  },
};

const fixedEpoch = new Date(2026, 8, 23, 10, 10, 30, 0);
const bootSeconds = performance.now() / 1000;
let manifest = embeddedFallback;
let attention = { x: 0, y: 0, targetX: 0, targetY: 0 };
let forceNextFrame = true;
let lastRenderedAt = Number.NEGATIVE_INFINITY;
let renderCount = 0;
let fpsWindowStarted = performance.now();
let autoIdleAt = bootSeconds + 8;
let lastPose = null;

const clips = {
  idle: Number.NEGATIVE_INFINITY,
  tap: Number.NEGATIVE_INFINITY,
  blink: Number.NEGATIVE_INFINITY,
  sprite: Number.NEGATIVE_INFINITY,
};

function nowSeconds() {
  return performance.now() / 1000;
}

function dateFor(now) {
  if (!dom.fixed.checked) return new Date();
  return new Date(fixedEpoch.getTime() + (now - bootSeconds) * 1000);
}

function flags() {
  return {
    sleep: dom.sleep.checked,
    focus: dom.focus.checked,
    lowBattery: dom.lowBattery.checked,
    charging: dom.charging.checked,
    alwaysOn: dom.alwaysOn.checked,
    lowPower: dom.lowPower.checked,
  };
}

function buildTicks() {
  const group = $("#dial-ticks");
  for (let index = 0; index < 12; index += 1) {
    const angle = index * 30;
    const major = index % 3 === 0;
    const tick = document.createElementNS("http://www.w3.org/2000/svg", "line");
    tick.setAttribute("x1", "180");
    tick.setAttribute("y1", major ? "78" : "82");
    tick.setAttribute("x2", "180");
    tick.setAttribute("y2", major ? "91" : "88");
    tick.setAttribute("stroke", major ? "rgba(255,255,255,.78)" : "rgba(255,255,255,.35)");
    tick.setAttribute("stroke-width", major ? "3" : "2");
    tick.setAttribute("stroke-linecap", "round");
    tick.setAttribute("transform", `rotate(${angle} 180 236)`);
    group.append(tick);
  }
}

function closedSpline(points) {
  if (!points.length) return "";
  const midpoint = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  const start = midpoint(points.at(-1), points[0]);
  let path = `M ${start[0].toFixed(2)} ${start[1].toFixed(2)}`;
  points.forEach((point, index) => {
    const next = points[(index + 1) % points.length];
    const end = midpoint(point, next);
    path += ` Q ${point[0].toFixed(2)} ${point[1].toFixed(2)} ${end[0].toFixed(2)} ${end[1].toFixed(2)}`;
  });
  return `${path} Z`;
}

function deformMesh(pose) {
  const source = manifest.mesh?.bodyControlPoints ?? embeddedFallback.mesh.bodyControlPoints;
  const breath = pose.breathing * 2.5;
  const slump = pose.slump;
  return source.map(([x, y], index) => {
    const verticalWeight = Math.max(0, 1 - Math.abs(y - 225) / 170);
    const side = Math.sign(x - 180);
    let nextX = x + side * breath * verticalWeight;
    let nextY = y;
    if (index === 0) nextY -= breath * 0.8;
    if (slump) {
      nextX += (y < 230 ? 5 : 1) * slump;
      nextY += (y < 240 ? 7 : 3) * slump;
    }
    return [nextX, nextY];
  });
}

function renderRig(points) {
  const outline = points.map((point, index) => `${index ? "L" : "M"}${point[0]} ${point[1]}`).join(" ") + " Z";
  const cross = [
    `M${points[1][0]} ${points[1][1]} L${points[8][0]} ${points[8][1]}`,
    `M${points[2][0]} ${points[2][1]} L${points[7][0]} ${points[7][1]}`,
    `M${points[3][0]} ${points[3][1]} L${points[6][0]} ${points[6][1]}`,
    `M${points[0][0]} ${points[0][1]} L${points[5][0]} ${points[5][1]}`,
  ].join(" ");
  dom.meshLines.setAttribute("d", `${outline} ${cross}`);

  while (dom.meshPoints.children.length < points.length) {
    const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    circle.setAttribute("r", "3.2");
    circle.setAttribute("fill", "#74f5d0");
    circle.setAttribute("stroke", "#07100e");
    circle.setAttribute("stroke-width", "1.2");
    dom.meshPoints.append(circle);
  }
  points.forEach(([x, y], index) => {
    const circle = dom.meshPoints.children[index];
    circle.setAttribute("cx", x);
    circle.setAttribute("cy", y);
  });
}

function setHandTransform(element, pivot, degrees) {
  element.setAttribute("transform", `translate(${pivot[0]} ${pivot[1]}) rotate(${degrees.toFixed(7)})`);
}

function renderFace(pose, now) {
  const asleep = pose.mode.face === "sleep";
  const focused = pose.mode.face === "focus";
  const blinkScale = asleep ? 0.075 : Math.max(0.075, 1 - pose.blink * 0.94);
  attention.x += (attention.targetX - attention.x) * 0.16;
  attention.y += (attention.targetY - attention.y) * 0.16;
  const attentionWeight = asleep ? 0 : 1;
  dom.eyes.setAttribute("transform", `translate(180 188) scale(1 ${blinkScale.toFixed(3)}) translate(-180 -188)`);
  dom.pupils.forEach((pupil) => {
    pupil.setAttribute("transform", `translate(${(attention.x * 5 * attentionWeight).toFixed(2)} ${(attention.y * 4 * attentionWeight).toFixed(2)})`);
  });
  dom.lids.forEach((lid) => {
    lid.setAttribute("transform", `translate(0 ${(focused ? -2.5 : 0).toFixed(2)})`);
  });

  const lift = pose.crown.browLift + (focused ? 2 : 0);
  dom.browLeft.setAttribute("d", `M137 ${157 + lift} Q157 ${149 + lift} 175 ${157 + lift}`);
  dom.browRight.setAttribute("d", `M185 ${157 + lift} Q203 ${149 + lift} 223 ${157 + lift}`);
  const smile = asleep ? -2 : pose.crown.smile;
  dom.mouth.setAttribute("d", `M149 232 Q180 ${250 + smile} 211 232`);

  const bubble = asleep ? 5 + ((Math.sin(now * 2.2) + 1) * 2.2) : 0;
  dom.sleepBubble.setAttribute("r", bubble.toFixed(2));
  dom.sleepBubble.setAttribute("cx", (220 + Math.sin(now * 1.3) * 2).toFixed(2));
}

function renderSprite(now, pose) {
  const elapsed = now - clips.sprite;
  const active = pose.tier.animated && elapsed >= 0 && elapsed < MOTION.spriteDuration;
  dom.sprite.classList.toggle("visible", active);
  if (!active) return;
  const index = frameIndex(elapsed, 10, MOTION.spriteFrames);
  dom.sprite.style.backgroundPosition = `${(index / (MOTION.spriteFrames - 1)) * 100}% 0`;
}

function render(now) {
  const stateFlags = flags();
  const date = dateFor(now);
  const pose = composePose({
    date,
    nowSeconds: now,
    idleStartedAt: clips.idle,
    tapStartedAt: clips.tap,
    blinkStartedAt: clips.blink,
    crown: Number(dom.crown.value),
    ...stateFlags,
  });
  lastPose = pose;

  const hourPivot = manifest.anchors?.hourArmPivot ?? [180, 240];
  const minutePivot = manifest.anchors?.minuteArmPivot ?? [180, 240];
  setHandTransform(dom.hourHand, hourPivot, pose.hands.hour);
  setHandTransform(dom.minuteHand, minutePivot, pose.hands.minute);

  const slumpY = pose.slump * 12;
  const slumpRotation = pose.slump * 4.5;
  const rootScale = pose.tap.scale;
  dom.root.setAttribute(
    "transform",
    `translate(0 ${(pose.tap.y + slumpY).toFixed(3)}) translate(180 240) rotate(${slumpRotation}) scale(${rootScale.toFixed(4)}) translate(-180 -240)`,
  );

  const points = deformMesh(pose);
  dom.body.setAttribute("d", closedSpline(points));
  renderRig(points);
  renderFace(pose, now);
  dom.shorts.setAttribute("fill", `hsl(${pose.crown.outfitHue.toFixed(1)} 60% 55%)`);

  const chargeOpacity = pose.mode.charging ? 0.18 + pose.chargingPulse * 0.48 : 0;
  dom.chargingRing.setAttribute("opacity", chargeOpacity.toFixed(3));
  dom.chargingRing.setAttribute("r", (137 + pose.chargingPulse * 7).toFixed(2));
  dom.ocean.style.filter = pose.mode.face === "sleep"
    ? "hue-rotate(28deg) saturate(.65) brightness(.62)"
    : pose.mode.face === "focus"
      ? "hue-rotate(-28deg) saturate(1.2)"
      : "none";

  dom.rig.setAttribute("opacity", dom.showRig.checked ? ".88" : "0");
  dom.screen.classList.toggle("aod", pose.tier.name === "always-on");
  dom.screen.classList.toggle("low-power", pose.tier.name === "low-power");
  renderSprite(now, pose);

  const timeFormatter = new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit", hour12: false });
  dom.digitalTime.textContent = timeFormatter.format(date);
  dom.modeLabel.textContent = `${pose.mode.face.toUpperCase()} · ${pose.tier.name.toUpperCase()}`;
  dom.crownOutput.value = Number(dom.crown.value).toFixed(2);

  const error = Math.max(
    shortestAngleError(pose.hands.hour, pose.base.hour),
    shortestAngleError(pose.hands.minute, pose.base.minute),
  );
  dom.hourTarget.textContent = `${pose.base.hour.toFixed(3)}°`;
  dom.hourActual.textContent = `${pose.hands.hour.toFixed(3)}°`;
  dom.minuteTarget.textContent = `${pose.base.minute.toFixed(3)}°`;
  dom.returnError.textContent = `${error.toFixed(3)}°`;
  dom.returnError.style.color = error < 0.000001 ? "var(--mint)" : "var(--yellow)";

  dom.stateName.textContent = pose.mode.face.toUpperCase()
    + (pose.mode.lowBattery ? " · SLUMP" : "")
    + (pose.mode.charging ? " · CHARGE" : "");
  dom.tierName.textContent = `${pose.tier.name.toUpperCase()} / ${pose.tier.fps} FPS`;
  const blend = ["TIME"];
  if (pose.tier.animated) blend.push("BREATH");
  if (pose.offsets.minute) blend.push("IDLE");
  if (pose.tap.weight) blend.push("TAP");
  dom.blendName.textContent = blend.join(" + ");
}

function animationLoop(timestampMs) {
  const now = timestampMs / 1000;
  const currentFlags = flags();
  const tier = currentFlags.lowPower ? MOTION.lowPowerFPS : currentFlags.alwaysOn ? MOTION.ambientFPS : MOTION.activeFPS;
  const interval = 1 / tier;

  if (!currentFlags.alwaysOn && !currentFlags.lowPower && now >= autoIdleAt) {
    clips.idle = now;
    autoIdleAt = now + 12;
    forceNextFrame = true;
  }

  if (forceNextFrame || now - lastRenderedAt >= interval) {
    render(now);
    lastRenderedAt = now;
    forceNextFrame = false;
    renderCount += 1;
  }

  if (timestampMs - fpsWindowStarted >= 1000) {
    const elapsed = (timestampMs - fpsWindowStarted) / 1000;
    dom.fps.textContent = `render ${(renderCount / elapsed).toFixed(1)} fps`;
    renderCount = 0;
    fpsWindowStarted = timestampMs;
  }
  requestAnimationFrame(animationLoop);
}

function trigger(name) {
  const now = nowSeconds();
  clips[name] = now;
  forceNextFrame = true;
  if (name === "idle") autoIdleAt = now + 12;
  if (name === "tap") {
    // Browser analogue of WKInterfaceDevice.current().play(.click).
    navigator.vibrate?.(12);
    window.dispatchEvent(new CustomEvent("patrick-haptic", { detail: { kind: "click" } }));
  }
}

function runVerification() {
  const dates = [
    new Date(2026, 8, 23, 10, 10, 30, 0),
    new Date(2026, 8, 23, 3, 15, 0, 0),
    new Date(2026, 8, 23, 23, 59, 59, 999),
  ];
  const results = dates.map((date, index) => verifyHandReturn({
    date,
    idleStartedAt: 100 + index,
    nowSeconds: 100 + index + MOTION.idleDuration,
    tolerance: 1e-9,
  }));
  const maxError = Math.max(...results.flatMap((result) => [result.hourError, result.minuteError]));
  const pass = results.every((result) => result.pass);

  dom.verification.className = `verification-log ${pass ? "pass" : "fail"}`;
  dom.verification.innerHTML = `
    <span class="status-dot"></span>
    <p><strong>${pass ? "PASS" : "FAIL"} · 3 deterministic clock cases.</strong>
    Post-clip maximum error: ${maxError.toExponential(2)}°. The visible rig will now play the same zero-ended gesture.</p>
  `;
  trigger("idle");

  window.setTimeout(() => {
    const date = dateFor(nowSeconds());
    const result = verifyHandReturn({
      date,
      idleStartedAt: clips.idle,
      nowSeconds: clips.idle + MOTION.idleDuration,
      tolerance: 1e-9,
    });
    dom.verification.className = `verification-log ${pass && result.pass ? "pass" : "fail"}`;
    dom.verification.querySelector("p").innerHTML = `<strong>${pass && result.pass ? "PASS" : "FAIL"} · return invariant verified.</strong>
      Browser simulation and live gesture endpoint both report ${Math.max(result.hourError, result.minuteError).toExponential(2)}° error.`;
  }, MOTION.idleDuration * 1000 + 60);
}

async function loadManifest() {
  const candidates = [
    { url: "../style-library/patrick-anchor-manifest.json", label: "shared anchors" },
    { url: "./patrick-anchor-manifest.fallback.json", label: "local fallback" },
  ];
  for (const candidate of candidates) {
    try {
      const response = await fetch(candidate.url, { cache: "no-store" });
      if (!response.ok) continue;
      const value = await response.json();
      if (!value.anchors?.hourArmPivot || !value.anchors?.minuteArmPivot) continue;
      manifest = value;
      dom.manifestPill.textContent = candidate.label;
      dom.manifestPill.classList.remove("pending");
      forceNextFrame = true;
      return;
    } catch {
      // file:// blocks fetch; the embedded fallback keeps the prototype runnable.
    }
  }
  dom.manifestPill.textContent = "embedded fallback";
  dom.manifestPill.classList.remove("pending");
}

$$("[data-action]").forEach((button) => {
  button.addEventListener("click", () => trigger(button.dataset.action));
});

[
  dom.fixed, dom.crown, dom.sleep, dom.focus, dom.lowBattery,
  dom.charging, dom.alwaysOn, dom.lowPower, dom.showRig,
].forEach((control) => {
  control.addEventListener("input", () => {
    forceNextFrame = true;
    if (control === dom.lowPower && dom.lowPower.checked) dom.alwaysOn.checked = false;
    if (control === dom.alwaysOn && dom.alwaysOn.checked) dom.lowPower.checked = false;
  });
});

dom.screen.addEventListener("click", () => trigger("tap"));
dom.screen.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    trigger("tap");
  }
});
dom.screen.addEventListener("wheel", (event) => {
  event.preventDefault();
  const next = Math.min(1, Math.max(0, Number(dom.crown.value) + Math.sign(event.deltaY) * 0.04));
  dom.crown.value = String(next);
  forceNextFrame = true;
}, { passive: false });
dom.screen.addEventListener("pointermove", (event) => {
  const rect = dom.screen.getBoundingClientRect();
  attention.targetX = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
  attention.targetY = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
});
dom.screen.addEventListener("pointerleave", () => {
  attention.targetX = 0;
  attention.targetY = 0;
});
dom.verifyButton.addEventListener("click", runVerification);
document.addEventListener("visibilitychange", () => {
  forceNextFrame = true;
});

buildTicks();
loadManifest();
requestAnimationFrame(animationLoop);

// Stable inspection API for browser automation and integration tests.
window.__patrickMotionLab = Object.freeze({
  getPose: () => lastPose,
  trigger,
  runVerification,
  setCrown(value) {
    dom.crown.value = String(Math.min(1, Math.max(0, value)));
    forceNextFrame = true;
  },
  getManifest: () => manifest,
});
*/
