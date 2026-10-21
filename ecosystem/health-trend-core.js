// Descriptive daily comparisons. No health score, diagnosis, device actions,
// storage, or access to real health data. Mirrors PatrickHealthTrend.swift.
export const METRICS = Object.freeze(['sleepHours', 'restingHeartRate', 'hrvSDNN']);
export const MINIMUM_DAYS = 7;
export const FRESHNESS_MS = 36 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const empty = (metric, reason, invalidPointCount = 0) => ({ metric, state: 'noData', reason,
  baselineCount: 0, invalidPointCount, current: null, baseline: null, delta: null });
const samePoint = (left, right) => ['metric', 'dayStartMS', 'dayEndMS', 'observedAtMS', 'value', 'sourceKey', 'sourceLabel']
  .every(key => left[key] === right[key]);
function validPoint(point, nowMS) {
  if (![point.dayStartMS, point.dayEndMS, point.observedAtMS, point.value].every(Number.isFinite)
    || point.dayStartMS <= 0 || point.dayStartMS > nowMS || point.dayEndMS <= point.dayStartMS
    || point.observedAtMS < point.dayStartMS || point.observedAtMS > point.dayEndMS || point.observedAtMS > nowMS
    || typeof point.sourceKey !== 'string' || !point.sourceKey.trim()
    || typeof point.sourceLabel !== 'string' || !point.sourceLabel.trim()) return false;
  const hours = (point.dayEndMS - point.dayStartMS) / HOUR_MS;
  if (hours < 22 || hours > 26) return false;
  return point.metric === 'sleepHours' ? point.value >= 0 && point.value <= hours
    : point.metric === 'restingHeartRate' ? point.value > 0 : point.value >= 0;
}
export function evaluateHealthTrends(input) {
  if (!input || !Number.isFinite(input.nowMS) || input.nowMS <= 0
    || !Number.isFinite(input.historyStartMS) || input.historyStartMS <= 0
    || input.historyStartMS > input.nowMS || input.nowMS - input.historyStartMS > 30 * 24 * HOUR_MS
    || !Array.isArray(input.points)) return METRICS.map(metric => empty(metric, 'invalidInput'));
  return METRICS.map(metric => {
    const scoped = input.points.filter(point => point && point.metric === metric
      && (!Number.isFinite(point.dayStartMS) || point.dayStartMS >= input.historyStartMS));
    const invalid = scoped.filter(point => !validPoint(point, input.nowMS)).length;
    if (invalid) return empty(metric, 'invalidPoint', invalid);
    const points = [];
    for (const point of scoped) if (!points.some(existing => samePoint(existing, point))) points.push({ ...point });
    points.sort((left, right) => left.dayStartMS - right.dayStartMS);
    if (!points.length) return empty(metric, 'noSamples');
    if (new Set(points.map(point => point.dayStartMS)).size !== points.length) return empty(metric, 'conflictingDay');
    if (points.some((point, index) => index > 0 && points[index - 1].dayEndMS > point.dayStartMS)) return empty(metric, 'overlappingDays');
    const current = points.at(-1);
    const previous = points.filter(point => point.dayEndMS <= current.dayStartMS);
    const history = previous.filter(point => point.sourceKey === current.sourceKey).slice(-28);
    const result = { metric, state: 'building', reason: history.length === 0 && previous.length > 0 ? 'sourceChanged' : 'insufficientHistory',
      baselineCount: history.length, invalidPointCount: 0, current, baseline: null, delta: null };
    if (input.nowMS - current.observedAtMS > FRESHNESS_MS) return { ...result, state: 'stale', reason: 'staleObservation' };
    if (history.length < MINIMUM_DAYS) return result;
    const values = history.map(point => point.value).sort((left, right) => left - right);
    const middle = Math.floor(values.length / 2);
    const baseline = values.length % 2 === 0 ? values[middle - 1] / 2 + values[middle] / 2 : values[middle];
    return { ...result, state: 'ready', reason: 'comparable', baseline, delta: current.value - baseline };
  });
}
// A self-report changes only this invitation. Metric values never choose it.
export function companionInvitation(feeling) {
  if (feeling === 'tired') return { mode: 'gentle', label: '溫柔一點的陪伴', title: '那今天，我小聲陪你。',
    text: '想先安靜一下也可以；等你想互動，再來找我。', reason: '因為你選了「有點累」，邀請語氣改得輕一些。這不是從數值判定你疲累。' };
  if (feeling === 'okay') return { mode: 'normal', label: '照你的步調', title: '好，那就一起過今天。',
    text: '想玩一下、換個造型，或只是看看時間，都可以。', reason: '因為你選了「還不錯」，保留平常的陪伴邀請。這不代表健康狀態已獲確認。' };
  return { mode: 'normal', label: '先聽你的', title: '不用急著替今天下結論。',
    text: '先保留平常的陪伴，等你想好再說。', reason: '你選了「還不確定」。派大星不替你猜，也不會因為缺少紀錄就替你改變步調。' };
}
