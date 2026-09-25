export const MOTION = Object.freeze({
  idleDuration: 1.8,
  tapDuration: 0.56,
  blinkDuration: 0.24,
  spriteDuration: 0.84,
  spriteFrames: 6,
  activeFPS: 30,
  ambientFPS: 1,
  lowPowerFPS: 0.2,
});

export const PRIORITY = Object.freeze({
  timekeeping: 1000, // Absolute base. Gestures are offsets and never replace it.
  safety: 900,       // Always-On / low-power simplification.
  directInput: 700,  // Tap and crown.
  mode: 500,         // Focus / sleep / battery / charging.
  idleClip: 300,
  breathing: 100,
});

export function clamp(value, min = 0, max = 1) {
  return Math.min(max, Math.max(min, value));
}

export function lerp(a, b, amount) {
  return a + (b - a) * amount;
}

export function smoothstep(edge0, edge1, value) {
  const x = clamp((value - edge0) / (edge1 - edge0));
  return x * x * (3 - 2 * x);
}

export function normalizeDegrees(value) {
  return ((value % 360) + 360) % 360;
}

export function shortestAngleError(actual, expected) {
  return Math.abs(((actual - expected + 540) % 360) - 180);
}

export function clockAngles(date) {
  const milliseconds = date.getMilliseconds();
  const second = date.getSeconds() + milliseconds / 1000;
  const minute = date.getMinutes() + second / 60;
  const hour = (date.getHours() % 12) + minute / 60;
  return {
    hour: normalizeDegrees(hour * 30),
    minute: normalizeDegrees(minute * 6),
    second: normalizeDegrees(second * 6),
  };
}

// A clip envelope with mathematically exact zero outside its duration.
export function clipEnvelope(elapsed, duration) {
  if (!Number.isFinite(elapsed) || elapsed <= 0 || elapsed >= duration) return 0;
  const progress = elapsed / duration;
  const sine = Math.sin(Math.PI * progress);
  return sine * sine;
}

export function idleOffsets(elapsed, duration = MOTION.idleDuration) {
  const weight = clipEnvelope(elapsed, duration);
  // Minute arm waves farther; hour arm counters slightly to preserve readability.
  return {
    hour: -5 * weight,
    minute: 19 * weight,
    weight,
  };
}

export function tapPose(elapsed, duration = MOTION.tapDuration) {
  const weight = clipEnvelope(elapsed, duration);
  return {
    y: -9 * weight,
    scale: 1 + 0.045 * weight,
    weight,
  };
}

export function blinkAmount(elapsed, duration = MOTION.blinkDuration) {
  return clipEnvelope(elapsed, duration);
}

export function frameIndex(elapsed, fps = 10, frameCount = MOTION.spriteFrames) {
  if (!Number.isFinite(elapsed) || elapsed < 0) return -1;
  return Math.floor(elapsed * fps) % frameCount;
}

export function performanceTier({ alwaysOn = false, lowPower = false } = {}) {
  if (lowPower) {
    return { name: "low-power", fps: MOTION.lowPowerFPS, animated: false };
  }
  if (alwaysOn) {
    return { name: "always-on", fps: MOTION.ambientFPS, animated: false };
  }
  return { name: "active", fps: MOTION.activeFPS, animated: true };
}

export function resolveMode({
  sleep = false,
  focus = false,
  lowBattery = false,
  charging = false,
} = {}) {
  // Mutually exclusive facial mode; battery and charging remain visual overlays.
  const face = sleep ? "sleep" : focus ? "focus" : "awake";
  return { face, lowBattery: Boolean(lowBattery), charging: Boolean(charging) };
}

export function crownParameters(value) {
  const normalized = clamp(Number(value), 0, 1);
  return {
    expression: normalized,
    outfitHue: lerp(76, 196, normalized),
    browLift: lerp(0, -5, normalized),
    smile: lerp(0, 8, normalized),
  };
}

export function composePose({
  date,
  nowSeconds,
  idleStartedAt = Number.NEGATIVE_INFINITY,
  tapStartedAt = Number.NEGATIVE_INFINITY,
  blinkStartedAt = Number.NEGATIVE_INFINITY,
  crown = 0,
  alwaysOn = false,
  lowPower = false,
  sleep = false,
  focus = false,
  lowBattery = false,
  charging = false,
} = {}) {
  const tier = performanceTier({ alwaysOn, lowPower });
  const mode = resolveMode({ sleep, focus, lowBattery, charging });
  const base = clockAngles(date);
  const idleElapsed = nowSeconds - idleStartedAt;
  const idle = tier.animated ? idleOffsets(idleElapsed) : idleOffsets(-1);
  const tap = tier.animated ? tapPose(nowSeconds - tapStartedAt) : tapPose(-1);
  const blink = tier.animated ? blinkAmount(nowSeconds - blinkStartedAt) : 0;
  const crownPose = crownParameters(crown);

  const hour = normalizeDegrees(base.hour + idle.hour);
  const minute = normalizeDegrees(base.minute + idle.minute);

  return {
    tier,
    mode,
    crown: crownPose,
    base,
    hands: { hour, minute },
    offsets: { hour: idle.hour, minute: idle.minute },
    tap,
    blink,
    breathing: tier.animated && mode.face !== "sleep"
      ? Math.sin(nowSeconds * Math.PI * 0.72)
      : 0,
    chargingPulse: tier.animated && charging
      ? (Math.sin(nowSeconds * Math.PI * 1.2) + 1) / 2
      : 0,
    slump: lowBattery ? 1 : 0,
  };
}

export function verifyHandReturn({
  date,
  nowSeconds,
  idleStartedAt,
  duration = MOTION.idleDuration,
  tolerance = 1e-9,
}) {
  const base = clockAngles(date);
  const pose = composePose({ date, nowSeconds, idleStartedAt });
  // Timeline clocks are floating-point seconds; accept sub-nanosecond subtraction drift.
  const clipFinished = nowSeconds - idleStartedAt >= duration - 1e-9;
  const hourError = shortestAngleError(pose.hands.hour, base.hour);
  const minuteError = shortestAngleError(pose.hands.minute, base.minute);
  return {
    pass: clipFinished && hourError <= tolerance && minuteError <= tolerance,
    clipFinished,
    hourError,
    minuteError,
    expected: base,
    actual: pose.hands,
  };
}
