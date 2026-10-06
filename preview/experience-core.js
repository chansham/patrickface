import { layoutID } from './layout-core.js?v=20261006-layouts1';
// Local companion state. None of these values represent health or sensor data.
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const number = (value, fallback) => Number.isFinite(value) ? value : fallback;
export const TIMER_KINDS = Object.freeze({ focus: '專心', exercise: '運動陪伴', walking: '散步', running: '跑步', strength: '肌力', breathing: '呼吸' });
export const isExerciseKind = kind => ['exercise', 'walking', 'running', 'strength'].includes(kind);
export const EXPERIENCE_KEY = 'patrick.experience.v1';
export function newExperience(now = Date.now()) {
  return { version: 1, outfitId: 'auto', settings: { sound: false, haptics: true, timeFormat: '24', clockMode: 'digital', bubbles: true, showDate: true,
    sleepStartMinutes: 1320, sleepEndMinutes: 360, holidaysEnabled: true, layoutID: 'classic' },
    care: { satiety: 60, bond: 0, updatedAt: now }, journal: [], activity: null, easterEggs: {} };
}
export function restoreExperience(raw, now = Date.now()) {
  const base = newExperience(now);
  if (raw?.version !== 1) return base;
  const preferences = raw.settings || {};
  base.outfitId = typeof raw.outfitId === 'string' ? raw.outfitId.slice(0, 100) : 'auto';
  base.settings = { sound: preferences.sound === true, haptics: preferences.haptics !== false,
    timeFormat: preferences.timeFormat === '12' ? '12' : '24', clockMode: preferences.clockMode === 'arms' ? 'arms' : 'digital',
    bubbles: preferences.bubbles !== false, showDate: preferences.showDate !== false, holidaysEnabled: preferences.holidaysEnabled !== false, layoutID: layoutID(preferences.layoutID),
    sleepStartMinutes: clamp(Math.floor(number(preferences.sleepStartMinutes, 1320)), 0, 1439),
    sleepEndMinutes: clamp(Math.floor(number(preferences.sleepEndMinutes, 360)), 0, 1439) };
  base.care = { satiety: clamp(number(raw.care?.satiety, 60), 0, 100), bond: clamp(number(raw.care?.bond, 0), 0, 100),
    updatedAt: Math.min(number(raw.care?.updatedAt, now), now) };
  base.journal = Array.isArray(raw.journal) ? raw.journal.filter(entry => typeof entry.id === 'string' && Number.isFinite(entry.at)
    && typeof entry.text === 'string' && typeof entry.type === 'string').slice(-60).map(entry => ({ ...entry, text: entry.text.slice(0, 300) })) : [];
  const timer = raw.activity;
  if (timer && Object.hasOwn(TIMER_KINDS, timer.kind) && typeof timer.id === 'string' && Number.isFinite(timer.durationMs)
      && timer.durationMs >= 10000 && timer.durationMs <= 7200000 && Number.isFinite(timer.startedAt)
      && (timer.paused === true ? Number.isFinite(timer.remainingMs) : Number.isFinite(timer.endsAt))) {
    base.activity = { id: timer.id, kind: timer.kind, durationMs: timer.durationMs, startedAt: timer.startedAt,
      paused: timer.paused === true, remainingMs: clamp(number(timer.remainingMs, timer.durationMs), 0, timer.durationMs),
      endsAt: timer.paused ? null : timer.endsAt, completedAt: Number.isFinite(timer.completedAt) ? timer.completedAt : null };
  }
  for (const [key, value] of Object.entries(raw.easterEggs || {})) if (/^[a-z0-9-]+$/.test(key) && Number.isFinite(value)) base.easterEggs[key] = Math.min(now, value);
  return base;
}
export function careNow(care, now = Date.now()) {
  const elapsedHours = Math.max(0, now - care.updatedAt) / 3600000;
  return { satiety: clamp(care.satiety - elapsedHours * 1.5, 0, 100), bond: care.bond, updatedAt: now };
}
export function appendJournal(state, type, text, now = Date.now()) {
  const entry = { id: `${now}-${state.journal.length}-${type}`, at: now, type, text };
  return { ...state, journal: [...state.journal, entry].slice(-60) };
}
export function careAction(state, action, now = Date.now()) {
  const care = careNow(state.care, now);
  if (action === 'feed') { care.satiety = Math.min(100, care.satiety + 12); care.bond = Math.min(100, care.bond + 2); }
  if (action === 'pet') care.bond = Math.min(100, care.bond + 1);
  return { ...state, care };
}
export function timerRemaining(activity, now = Date.now()) {
  if (!activity || activity.completedAt !== null) return 0;
  return activity.paused ? activity.remainingMs : clamp(activity.endsAt - now, 0, activity.durationMs);
}
export function startActivity(state, kind, seconds, now = Date.now()) {
  if (!Object.hasOwn(TIMER_KINDS, kind)) return state;
  const durationMs = clamp(number(seconds, 60), 10, 7200) * 1000;
  return { ...state, activity: { id: `${now}-${kind}`, kind, durationMs, startedAt: now, endsAt: now + durationMs,
    paused: false, remainingMs: durationMs, completedAt: null } };
}
export function pauseActivity(state, now = Date.now()) {
  if (!state.activity || state.activity.paused || state.activity.completedAt !== null) return state;
  const remainingMs = timerRemaining(state.activity, now);
  // Finishing and pausing are different events; do not turn a finished timer into
  // an indefinitely paused zero-second session.
  if (!remainingMs) return state;
  return { ...state, activity: { ...state.activity, paused: true, endsAt: null, remainingMs } };
}
export function resumeActivity(state, now = Date.now()) {
  if (!state.activity?.paused || state.activity.completedAt !== null) return state;
  return { ...state, activity: { ...state.activity, paused: false, endsAt: now + state.activity.remainingMs } };
}
export function finishActivity(state, now = Date.now()) {
  if (!state.activity || state.activity.paused || state.activity.completedAt !== null || timerRemaining(state.activity, now)) return state;
  const next = { ...state, activity: { ...state.activity, completedAt: now, remainingMs: 0 } };
  return appendJournal(next, 'complete', `${TIMER_KINDS[state.activity.kind]}完成了 ${Math.round(state.activity.durationMs / 1000)} 秒。`, now);
}
export function cancelActivity(state) { return { ...state, activity: null }; }
export function controlActivity(state, action, now = Date.now()) {
  if (!['pause', 'resume', 'cancel'].includes(action)) return { state, status: 'invalid' };
  const settled = finishActivity(state, now), activity = settled.activity;
  if (!activity) return { state: settled, status: 'no-active' };
  if (activity.completedAt !== null) return { state: settled, status: 'completed' };
  if (action === 'pause') return activity.paused ? { state: settled, status: 'already-paused' }
    : { state: pauseActivity(settled, now), status: 'paused' };
  if (action === 'resume') return !activity.paused ? { state: settled, status: 'already-running' }
    : { state: resumeActivity(settled, now), status: 'resumed' };
  return { state: appendJournal(cancelActivity(settled), 'cancel', '這一段先結束，沒有算作完成。', now), status: 'cancelled' };
}
export function claimEgg(state, id, cooldownMs, now = Date.now()) {
  const previous = state.easterEggs[id];
  if (Number.isFinite(previous) && Math.max(0, now - previous) < cooldownMs) return { state, claimed: false };
  return { state: { ...state, easterEggs: { ...state.easterEggs, [id]: now } }, claimed: true };
}
export function clockAngles(date) {
  const minute = date.getMinutes() + date.getSeconds() / 60;
  return { hour: ((date.getHours() % 12) + minute / 60) * Math.PI / 6, minute: minute * Math.PI / 30 };
}
export function isSleepMinute(minute, start, end) {
  if (start === end) return false;
  return start < end ? minute >= start && minute < end : minute >= start || minute < end;
}
