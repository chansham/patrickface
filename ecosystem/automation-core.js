// Browser simulation only. No device permissions, transport or health data.
export const FRESH_MS = 3000;
export const MAX_RECEIPTS = 100;
export const kinds = Object.freeze({ 'alarm-stopped': '鬧鐘已停止', 'wake-up': '我起床了' });
export function receiveEvent(previous, event, context) {
  const seen = Array.isArray(previous) ? previous.slice(-MAX_RECEIPTS) : [];
  const valid = event && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(event.id || '')
    && Object.hasOwn(kinds, event.kind) && ['shortcut', 'manual'].includes(event.source)
    && Number.isFinite(event.occurredAtMS) && event.occurredAtMS > 0 && Number.isFinite(context.now)
    && event.occurredAtMS <= context.now;
  if (!valid) return { seen, accepted: false, animate: false, reason: 'invalid', text: '事件格式或時間不正確，沒有採用。' };
  const id = event.id.toLowerCase();
  if (seen.includes(id)) return { seen, accepted: false, animate: false, reason: 'duplicate', text: '這個事件已處理，不再重播。' };
  const next = [...seen, id].slice(-MAX_RECEIPTS);
  if (context.now - event.occurredAtMS > FRESH_MS) return { seen: next, accepted: true, animate: false, reason: 'stale', text: '收到延遲事件，只留記錄，不補播舊動畫。' };
  if (!context.visible || context.quiet || event.occurredAtMS < context.visibleSinceMS) return { seen: next, accepted: true, animate: false, reason: 'quiet', text: '收到事件；目前不適合播放，這次略過，不留待播。' };
  return { seen: next, accepted: true, animate: true, reason: 'fresh', text: '收到新的起床事件，派大星回應一次。' };
}
export class AutomationGate {
  constructor(seen = []) { this.seen = seen.slice(-MAX_RECEIPTS); this.active = false; this.visibleSinceMS = Infinity; }
  setPresentationActive(active, now) {
    if (active && !this.active) this.visibleSinceMS = now;
    if (!active) this.visibleSinceMS = Infinity;
    this.active = active;
  }
  consume(event, now) {
    const result = receiveEvent(this.seen, event, { now, visible: this.active, quiet: false, visibleSinceMS: this.visibleSinceMS });
    this.seen = result.seen;
    return { ...result, outcome: result.animate ? 'play' : result.accepted ? 'recordOnly' : result.reason };
  }
}
