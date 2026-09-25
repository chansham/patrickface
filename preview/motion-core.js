export const MOTION = Object.freeze({
  idleDuration: 1.8,
  tapDuration: 0.56,
  activeFPS: 30,
  ambientFPS: 1,
  lowPowerFPS: 0.2,
});

export function clamp(value, min = 0, max = 1) {
  return Math.min(max, Math.max(min, value));
}

export function normalizeDegrees(value) {
  return ((value % 360) + 360) % 360;
}

export function shortestAngleError(actual, expected) {
  return Math.abs(((actual - expected + 540) % 360) - 180);
}

export function clockAngles(date) {
  const second = date.getSeconds() + date.getMilliseconds() / 1000;
  const minute = date.getMinutes() + second / 60;
  const hour = (date.getHours() % 12) + minute / 60;
  return {
    hour: normalizeDegrees(hour * 30),
    minute: normalizeDegrees(minute * 6),
    second: normalizeDegrees(second * 6),
  };
}

export function clipEnvelope(elapsed, duration) {
  if (!Number.isFinite(elapsed) || elapsed <= 0 || elapsed >= duration) return 0;
  const progress = elapsed / duration;
  const sine = Math.sin(Math.PI * progress);
  return sine * sine;
}

export function idleOffsets(elapsed, duration = MOTION.idleDuration) {
  const weight = clipEnvelope(elapsed, duration);
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

export function composePose({
  date,
  nowSeconds,
  idleStartedAt = Number.NEGATIVE_INFINITY,
  tapStartedAt = Number.NEGATIVE_INFINITY,
  sleep = false,
  lowBattery = false,
  charging = false,
  alwaysOn = false,
} = {}) {
  const base = clockAngles(date);
  const animated = !alwaysOn;
  const idle = animated ? idleOffsets(nowSeconds - idleStartedAt) : idleOffsets(-1);
  const tap = animated ? tapPose(nowSeconds - tapStartedAt) : tapPose(-1);

  return {
    base,
    hands: {
      hour: normalizeDegrees(base.hour + idle.hour),
      minute: normalizeDegrees(base.minute + idle.minute),
    },
    offsets: { hour: idle.hour, minute: idle.minute },
    idleWeight: idle.weight,
    tap,
    sleep,
    lowBattery,
    charging,
    breathing: animated && !sleep ? Math.sin(nowSeconds * Math.PI * 0.72) : 0,
    chargingPulse: animated && charging
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
  const clipFinished = nowSeconds - idleStartedAt >= duration - 1e-9;
  const hourError = shortestAngleError(pose.hands.hour, base.hour);
  const minuteError = shortestAngleError(pose.hands.minute, base.minute);
  return {
    pass: clipFinished && hourError <= tolerance && minuteError <= tolerance,
    clipFinished,
    hourError,
    minuteError,
  };
}
