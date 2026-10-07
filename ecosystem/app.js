import { AutomationGate, kinds } from './automation-core.js';
import { resource, decodeJSON, loadClip, frameGeometry } from '../size-review/render-core.js?v=20261006-size5';
import { frameAt } from '../preview/player-core.js?v=20261006-layouts1';
const $ = selector => document.querySelector(selector), repo = new URL('../', import.meta.url);
const reduced = matchMedia('(prefers-reduced-motion: reduce)'), gate = new AutomationGate();
let clip, catalog, layout, raf = null, lastEvent = null, cards = [], selected = '全部';
const report = { status: 'loading', playing: false, playedEvents: 0, frames: [], outcome: null, simulatedOnly: true };
window.__patrickEcosystem = report;
function draw(index) {
  const canvas = $('#watch'), ctx = canvas.getContext('2d'), g = frameGeometry(clip, index, catalog.master, layout);
  ctx.clearRect(0, 0, 832, 992); ctx.fillStyle = '#070609'; ctx.fillRect(0, 0, 832, 992);
  ctx.drawImage(g.source, 0, 0, g.source.width, g.source.height, ...g.rect);
  ctx.fillStyle = '#f5f0e8'; ctx.textAlign = 'center'; ctx.font = '108px "Segoe UI",sans-serif'; ctx.fillText('07:30', 416, 140);
  ctx.fillStyle = '#9fafa9'; ctx.font = '36px "Microsoft JhengHei",sans-serif'; ctx.fillText('模擬早晨', 416, 215);
  canvas.dataset.frame = index;
  if (report.playing && !report.frames.includes(index)) report.frames.push(index);
}
function stop() { cancelAnimationFrame(raf); raf = null; report.playing = false; }
function presentation() {
  const active = !document.hidden && $('#visible').checked && !$('#quiet').checked && !reduced.matches;
  gate.setPresentationActive(active, Date.now()); if (!active) stop();
}
function play() {
  stop(); report.playing = true; report.playedEvents++; report.frames = [];
  const start = performance.now();
  function tick(now) { if (!report.playing) return; const elapsed = now - start; draw(frameAt(clip, elapsed));
    if (elapsed >= clip.ends.at(-1)) { stop(); return; } raf = requestAnimationFrame(tick); }
  draw(0); raf = requestAnimationFrame(tick);
}
function receive(event) {
  presentation(); const result = gate.consume(event, Date.now()); report.outcome = result.outcome; report.reason = result.reason;
  $('#delivery-result').textContent = result.text;
  const item = document.createElement('li'); item.textContent = `${kinds[event.kind]} · ${result.text}`;
  $('#events').prepend(item); while ($('#events').children.length > 5) $('#events').lastChild.remove();
  if (result.animate) play();
}
$('#send').addEventListener('click', () => {
  const kind = $('#event-kind').value, delay = $('#delivery').value;
  lastEvent = { id: crypto.randomUUID(), kind, source: kind === 'alarm-stopped' ? 'shortcut' : 'manual', occurredAtMS: Date.now() + (delay === 'late' ? -600000 : delay === 'future' ? 60000 : 0) };
  receive(lastEvent); $('#repeat').disabled = false;
});
$('#repeat').addEventListener('click', () => { if (lastEvent) receive(lastEvent); });
for (const id of ['#visible', '#quiet']) $(id).addEventListener('change', presentation);
document.addEventListener('visibilitychange', presentation); reduced.addEventListener('change', presentation);
function showCards() {
  $('#cards').replaceChildren(); const visible = cards.filter(card => selected === '全部' || card.group === selected);
  $('#map-count').textContent = `${visible.length} 個用途 · 實作狀態逐項列明`;
  for (const card of visible) {
    const article = document.createElement('article'); article.className = 'card';
    for (const [tag, className, text] of [['span','label',card.status], ['h3','',card.title], ['p','',card.experience], ['p','boundary',card.boundary]]) {
      const node = document.createElement(tag); node.className = className; node.textContent = text; article.append(node);
    }
    const a = document.createElement('a'); a.href = card.reference; a.textContent = '查看依據與接法 ↗'; article.append(a); $('#cards').append(article);
  }
  for (const button of $('#filters').children) button.setAttribute('aria-pressed', String(button.textContent === selected));
}
try {
  const [c,l,map] = await Promise.all(['animation/catalog.json','experience/layouts.json','ecosystem/capabilities.json'].map(async path => decodeJSON(await resource(path,repo))));
  catalog = c; layout = l.layouts.find(item => item.id === 'classic'); cards = map.items;
  for (const name of ['全部', ...new Set(cards.map(card => card.group))]) { const b = document.createElement('button'); b.textContent = name; b.addEventListener('click', () => { selected = name; showCards(); }); $('#filters').append(b); }
  showCards(); clip = await loadClip(catalog.clips.find(item => item.id === 'wake'), repo, new Map()); draw(0); presentation();
  $('#send').disabled = false; $('#delivery-result').textContent = '選一個情況，試試派大星怎樣回應。'; report.status = 'ready'; report.frameCount = clip.frameCount;
} catch (error) { report.status = 'error'; report.error = error.message; $('#delivery-result').textContent = `畫稿或資料載入失敗：${error.message}。重新整理可重試。`; }
