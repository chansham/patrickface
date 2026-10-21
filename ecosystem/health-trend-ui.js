import { evaluateHealthTrends, companionInvitation } from './health-trend-core.js?v=20261013-health1';
import { resource, decodeJSON, loadClip, frameGeometry } from '../size-review/render-core.js?v=20261006-size5';
const $ = selector => document.querySelector(selector);
const definitions = {
  sleepHours: { title: '記錄到的睡眠', unit: '小時', precision: 1 },
  restingHeartRate: { title: '靜止心率', unit: '次／分鐘', precision: 1 },
  hrvSDNN: { title: '心率變異・SDNN', unit: '毫秒', precision: 1 },
};
const states = { ready: '可以比較', building: '建立基準中', stale: '最後紀錄已舊', noData: '暫無可用比較' };
const presets = {
  'presentation-ready': ['已有一段同來源紀錄', '三個項目分別和自己的過去比較。數字的變化不會替你選擇今天的陪伴語氣。'],
  'mixed-missing': ['只有部分項目有紀錄', '有資料的項目照常描述；沒有 HRV 紀錄時，獨立顯示沒有資料，不補成零。'],
  building: ['剛開始累積紀錄', '同來源的有效過往天數不足 7 天。可以看到最後一筆，但先不計算個人差值。'],
  'source-change': ['換了裝置或資料來源', '保留新來源的紀錄，重新累積可比較的日子。舊來源的天數不混進新基準。'],
  stale: ['最後同步停在幾天前', '距最後觀測超過 36 小時，只列最後紀錄。它不能代表你此刻的狀態。'],
  'no-data': ['目前沒有紀錄', '沒有紀錄可能有多種原因。這一頁不猜測你是否拒絕授權，也不把空值當成正常。'],
  'conflicting-day': ['同一天出現矛盾紀錄', '同一天有不同的日彙總，先停止該項比較，避免把不確定的資料算成可靠趨勢。'],
};
let cases = new Map(), feeling = 'unsure';
const report = { syntheticOnly: true, status: 'loading', selected: null, feeling, results: [], invitation: null, art: 'loading' };
window.__patrickHealthTrend = report;
const number = (value, precision = 1) => Number.isFinite(value) ? new Intl.NumberFormat('zh-Hant', { maximumFractionDigits: precision }).format(value) : '—';
const date = value => new Intl.DateTimeFormat('zh-Hant', { timeZone: 'Asia/Hong_Kong', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(value);
function el(tag, className, text) { const node = document.createElement(tag); node.className = className; if (text !== undefined) node.textContent = text; return node; }
function reason(result) {
  switch (result.reason) {
    case 'comparable': return `使用 ${result.baselineCount} 天同來源的過往紀錄；本次紀錄不算進基準。虛線是過往中位數，粉點是本次；缺日不連線。`;
    case 'insufficientHistory': return `目前有 ${result.baselineCount} 天同來源的過往紀錄，至少需要 7 天才顯示比較。`;
    case 'sourceChanged': return '新來源尚無可比較的過往日紀錄；不沿用舊來源的基準。';
    case 'staleObservation': return '最後觀測距試演時間已超過 36 小時，暫不顯示基準或差值。';
    case 'noSamples': return '沒有可用紀錄；不判定為正常，也不推測授權狀態。';
    case 'conflictingDay': return '同一天的日彙總互相矛盾，這一項暫不比較。';
    case 'overlappingDays': return '日紀錄的時間區間重疊，這一項暫不比較。';
    case 'invalidPoint': return `有 ${result.invalidPointCount} 筆資料的時間、數值或來源不完整，這一項暫不比較。`;
    default: return '比較條件不完整，暫不顯示結果。';
  }
}
function chart(result, input) {
  if (result.state !== 'ready') return el('div', 'empty-chart', result.state === 'building' ? '累積中 · 不畫成已建立的趨勢' : '此情況暫不繪製比較線');
  const points = input.points.filter(point => point.metric === result.metric && point.sourceKey === result.current.sourceKey
    && point.dayStartMS >= input.historyStartMS && point.dayStartMS <= result.current.dayStartMS)
    .filter((point, index, all) => all.findIndex(other => other.dayStartMS === point.dayStartMS) === index)
    .sort((left, right) => left.dayStartMS - right.dayStartMS).slice(-29);
  const values = points.map(point => point.value), minimum = Math.min(...values, result.baseline), maximum = Math.max(...values, result.baseline);
  const padding = Math.max((maximum - minimum) * .2, Math.abs(result.baseline) * .03, .1), low = minimum - padding, high = maximum + padding;
  const start = points[0].dayStartMS, duration = Math.max(1, points.at(-1).dayStartMS - start);
  const x = point => 5 + (point.dayStartMS - start) / duration * 280, y = value => 50 - (value - low) / (high - low) * 45;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); svg.setAttribute('viewBox', '0 0 290 55'); svg.setAttribute('class', 'metric-chart');
  svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', `${definitions[result.metric].title}合成紀錄趨勢，過往中位數 ${number(result.baseline)} ${definitions[result.metric].unit}，本次 ${number(result.current.value)} ${definitions[result.metric].unit}；缺日不連線`);
  const shapes = [['line', { class: 'base', x1: 5, x2: 285, y1: y(result.baseline), y2: y(result.baseline) }]];
  for (let index = 1; index < points.length; index++) {
    const previous = points[index - 1], current = points[index];
    if (previous.dayEndMS === current.dayStartMS) shapes.push(['line', { class: 'trend', x1: x(previous), y1: y(previous.value), x2: x(current), y2: y(current.value),
      'data-from-end-ms': previous.dayEndMS, 'data-to-start-ms': current.dayStartMS }]);
  }
  for (const [index, point] of points.entries()) shapes.push(['circle', { class: index === points.length - 1 ? 'current-point' : 'history-point',
    cx: x(point), cy: y(point.value), r: index === points.length - 1 ? 3.8 : 2.5, 'data-day-start-ms': point.dayStartMS }]);
  for (const [tag, attrs] of shapes) {
    const node = document.createElementNS('http://www.w3.org/2000/svg', tag); for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value)); svg.append(node);
  }
  return svg;
}
function renderMetric(result, input) {
  const definition = definitions[result.metric], card = el('article', 'metric'); card.dataset.metric = result.metric; card.dataset.state = result.state;
  const heading = el('div', 'metric-heading'); heading.append(el('h3', '', definition.title), el('span', 'metric-state', states[result.state]));
  const value = el('p', 'metric-value', number(result.current?.value, definition.precision)); value.append(el('small', '', definition.unit));
  let difference = '先不計算個人差值';
  if (result.state === 'ready') {
    const change = Math.abs(result.delta) < .01 ? '不足 0.01' : number(Math.abs(result.delta), 2);
    difference = result.delta === 0 ? `與過往中位數 ${number(result.baseline, 2)} ${definition.unit} 相同`
      : `過往中位數 ${number(result.baseline, 2)} ${definition.unit} · 本次${result.delta > 0 ? '多' : '少'} ${change} ${definition.unit}`;
  }
  if (result.state === 'noData') difference = '空值不代表零或正常';
  const meta = result.current ? `合成來源：${result.current.sourceLabel} · 最後觀測 ${date(result.current.observedAtMS)}（香港時間）`
    : '本項沒有可顯示的完整日彙總';
  card.append(heading, value, el('p', 'metric-delta', difference), chart(result, input), el('p', 'metric-meta', meta));
  if (result.current) card.append(el('p', 'metric-window', `本次區間 ${date(result.current.dayStartMS)} → ${date(result.current.dayEndMS)}（香港時間）`));
  card.append(el('p', 'metric-explanation', reason(result)));
  return card;
}
function renderFeeling() {
  const invitation = companionInvitation(feeling); report.feeling = feeling; report.invitation = invitation;
  for (const button of $('#feelings').querySelectorAll('button')) button.setAttribute('aria-pressed', String(button.dataset.feeling === feeling));
  for (const key of ['label', 'title', 'text', 'reason']) $(`#invitation-${key}`).textContent = invitation[key];
  $('.invitation').dataset.mode = invitation.mode;
}
function renderScenario() {
  const id = $('#scenario').value, test = cases.get(id); if (!test) return;
  const results = evaluateHealthTrends(test.input); report.selected = id; report.results = results;
  $('#scenario-note').textContent = `${presets[id][1]} 試演時間：${date(test.input.nowMS)}（香港時間）。`;
  $('#metrics').replaceChildren(...results.map(result => renderMetric(result, test.input)));
}
$('#scenario').addEventListener('change', renderScenario);
for (const button of $('#feelings').querySelectorAll('button')) button.addEventListener('click', () => { feeling = button.dataset.feeling; renderFeeling(); });
renderFeeling();
try {
  const response = await fetch('./health-trend-fixtures.json'); if (!response.ok) throw new Error(`範例讀取失敗 (${response.status})`);
  const fixtures = await response.json(); cases = new Map(fixtures.cases.map(test => [test.id, test]));
  const options = Object.entries(presets).filter(([id]) => cases.has(id)).map(([id, [title]]) => { const option = el('option', '', title); option.value = id; return option; });
  if (!options.length) throw new Error('缺少試演情境');
  $('#scenario').replaceChildren(...options); $('#scenario').disabled = false; renderScenario();
  report.status = 'ready'; document.documentElement.dataset.healthTrend = 'ready';
} catch (error) {
  report.status = 'error'; report.error = error.message; document.documentElement.dataset.healthTrend = 'error';
  $('#scenario-note').textContent = `暫時無法載入試演：${error.message}。重新整理可以重試。`;
}
// Use the existing full-frame renderer without generating or altering artwork.
try {
  const repo = new URL('../', import.meta.url), [catalog, layouts] = await Promise.all(['animation/catalog.json', 'experience/layouts.json'].map(async path => decodeJSON(await resource(path, repo))));
  const clip = await loadClip(catalog.clips.find(item => item.id === 'wake'), repo, new Map());
  const geometry = frameGeometry(clip, 0, catalog.master, layouts.layouts.find(item => item.id === 'classic'));
  const canvas = $('#watch-preview'), ctx = canvas.getContext('2d'); ctx.fillStyle = '#090b0c'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(geometry.source, 0, 0, geometry.source.width, geometry.source.height, ...geometry.rect);
  ctx.fillStyle = '#f4f0e6'; ctx.textAlign = 'center'; ctx.font = '104px "Segoe UI",sans-serif'; ctx.fillText('08:30', 416, 146);
  ctx.fillStyle = '#bfd4c5'; ctx.font = '36px "Microsoft JhengHei",sans-serif'; ctx.fillText('照你的步調', 416, 216);
  $('#art-status').textContent = '現有起床畫稿 · 靜態示意'; report.art = 'ready';
} catch (error) { $('#art-status').textContent = '現有畫稿暫未載入，資料試演仍可使用。'; report.art = 'unavailable'; report.artError = error.message; }
