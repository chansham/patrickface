// Deterministic, device-independent behaviour. Inputs in the browser are simulations.
import { LUNAR_HOLIDAYS } from "./holiday-calendar.js?v=20260927-experience2";
export const MODES = Object.freeze({
  auto: "跟隨時間", awake: "日常陪伴", sleeping: "睡覺", charging: "充電小劇場",
  walking: "散步陪伴", running: "跑步陪伴", strength: "組間休息", stretching: "伸展陪伴",
  breathing: "一起呼吸", focus: "專心一下", celebrate: "慶祝", rainy: "下雨天",
});
export const MOODS = Object.freeze({ happy: "開心", calm: "平靜", serious: "認真", tired: "疲倦", grumpy: "鬧脾氣", low: "低落" });
const finite = (n, fallback) => Number.isFinite(n) ? n : fallback;
const bound = (n, min, max) => Math.max(min, Math.min(max, n));

export function newPet(now = Date.now()) {
  return { version: 1, mode: "auto", theme: "cel", sleepStart: 23, sleepEnd: 7,
    birthday: "", mood: null, fed: 0, taps: 0, lastFedAt: null, lastSeenAt: now,
    activity: null, recent: [], lastEvent: null };
}

export function restorePet(raw, now = Date.now()) {
  const base = newPet(now);
  if (!raw || raw.version !== 1) return base;
  return { ...base,
    mode: Object.hasOwn(MODES, raw.mode) ? raw.mode : base.mode,
    theme: raw.theme === "toon3d" ? "toon3d" : "cel",
    sleepStart: bound(Math.floor(finite(raw.sleepStart, 23)), 0, 23),
    sleepEnd: bound(Math.floor(finite(raw.sleepEnd, 7)), 0, 23),
    birthday: validBirthday(raw.birthday) ? raw.birthday : "",
    mood: Object.hasOwn(MOODS, raw.mood) ? raw.mood : null,
    fed: bound(Math.floor(finite(raw.fed, 0)), 0, 99999),
    taps: bound(Math.floor(finite(raw.taps, 0)), 0, 99999),
    lastFedAt: Number.isFinite(raw.lastFedAt) ? Math.min(raw.lastFedAt, now) : null,
    lastSeenAt: Math.min(finite(raw.lastSeenAt, now), now),
    activity: raw.activity && Object.hasOwn(MODES, raw.activity.mode)
      && Number.isFinite(raw.activity.endsAt) && Number.isFinite(raw.activity.startedAt)
      && raw.activity.endsAt > raw.activity.startedAt
      ? { mode: raw.activity.mode, startedAt: raw.activity.startedAt, endsAt: raw.activity.endsAt } : null,
    recent: Array.isArray(raw.recent) ? raw.recent.filter(x => typeof x === "string").slice(-12) : [],
  };
}

export function isSleepHour(hour, start = 23, end = 7) {
  if (start === end) return false;
  return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}

export function validBirthday(value) {
  if (typeof value !== 'string' || !/^\d{2}-\d{2}$/.test(value)) return false;
  const [month, day] = value.split('-').map(Number), date = new Date(Date.UTC(2000, month - 1, day));
  return date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}
export function holidayFor(date, birthday = "") {
  const md = `${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  if (birthday && md === birthday) return { id: "birthday", name: "生日", motif: "cake" };
  const solar = { "01-01": ["new-year", "新年", "confetti"], "02-14": ["valentine", "情人節", "heart"],
    "10-31": ["halloween", "萬聖節", "pumpkin"], "12-24": ["christmas-eve", "平安夜", "snow"],
    "12-25": ["christmas", "聖誕節", "snow"] };
  if (solar[md]) { const [id, name, motif] = solar[md]; return { id, name, motif }; }
  // Some ICU releases disagree with the Hong Kong calendar (2027-02-06).
  // Out-of-range lunar dates stay unknown rather than silently guessing.
  return LUNAR_HOLIDAYS[`${date.getFullYear()}-${md}`] ?? null;
}

export function dispatch(pet, event, now = Date.now()) {
  const next = restorePet(pet, now);
  next.lastEvent = { type: event.type, at: now };
  switch (event.type) {
    case "mode": if (Object.hasOwn(MODES, event.value)) { next.mode = event.value; next.activity = null; } break;
    case "theme": next.theme = event.value === "toon3d" ? "toon3d" : "cel"; break;
    case "mood": if (Object.hasOwn(MOODS, event.value)) next.mood = event.value; else if (event.value === "") next.mood = null; break;
    case "feed":
      if (next.lastFedAt !== null && now - next.lastFedAt < 3000) return { ...pet, lastEvent: { type: "full", at: now } };
      next.fed = Math.min(99999, next.fed + 1); next.lastFedAt = now; break;
    case "tap": next.taps = Math.min(99999, next.taps + 1); break;
    case "timer": {
      const duration = bound(finite(event.seconds, 60), 10, 7200);
      const mode = Object.hasOwn(MODES, event.mode) ? event.mode : "focus";
      next.activity = { mode, startedAt: now, endsAt: now + duration * 1000 };
      next.mode = "auto"; break;
    }
    case "stop": next.activity = null; next.mode = "auto"; break;
    case "nfc-bed": next.mode = "sleeping"; next.activity = null; break;
    case "nfc-desk": next.mode = "auto"; next.activity = { mode: "focus", startedAt: now, endsAt: now + 25 * 60 * 1000 }; break;
    case "nfc-gym": next.mode = "strength"; next.activity = null; break;
    case "birthday": next.birthday = validBirthday(event.value) ? event.value : ""; break;
    case "sleep-window":
      next.sleepStart = bound(Math.floor(finite(event.start, 23)), 0, 23);
      next.sleepEnd = bound(Math.floor(finite(event.end, 7)), 0, 23); break;
    default: return pet;
  }
  next.lastSeenAt = now;
  next.recent = [...next.recent, event.type].slice(-12);
  return next;
}

export function resolveScene(pet, context, date = new Date()) {
  const now = finite(context.now, date.getTime());
  const activity = pet.activity;
  const running = activity && activity.endsAt > now;
  const completed = activity && activity.endsAt <= now;
  const holiday = holidayFor(date, pet.birthday);
  // Explicit rest wins. Charging replaces an automatic activity only while charging.
  let mode = pet.mode;
  let reason = mode === "auto" ? "按時間安排" : "手動選擇";
  if (mode === "auto") {
    if (context.charging) { mode = "charging"; reason = "充電狀態"; }
    else if (running) { mode = activity.mode; reason = "進行中的計時"; }
    else if (completed) { mode = "celebrate"; reason = "計時完成"; }
    else if (isSleepHour(date.getHours(), pet.sleepStart, pet.sleepEnd)) { mode = "sleeping"; reason = "設定的睡眠時段"; }
    else if (holiday) { mode = "celebrate"; reason = holiday.name; }
    else { mode = "awake"; }
  }
  const subdued = Boolean(context.reducedMotion || context.alwaysOn || context.lowBattery);
  return { mode, reason, holiday, subdued, charging: Boolean(context.charging || mode === "charging"),
    sleeping: mode === "sleeping", activityComplete: Boolean(completed),
    remaining: running ? Math.max(0, Math.ceil((activity.endsAt - now) / 1000)) : 0,
    progress: activity ? bound((now - activity.startedAt) / (activity.endsAt - activity.startedAt), 0, 1) : 0,
    mood: pet.mood, greeting: now - pet.lastSeenAt > 6 * 3600 * 1000 ? "你回來啦！" : null };
}

export function idleAction(bucket, previous = "") {
  const actions = ["wave", "peek", "bounce", "breathe"];
  let index = (Math.imul(Math.floor(bucket), 2654435761) >>> 0) % actions.length;
  if (actions[index] === previous) index = (index + 1) % actions.length;
  return actions[index];
}
