import { AftercarePolicy } from '../preview/aftercare-core.js?v=20261013-aftercare1';
import { frameAt } from '../preview/player-core.js?v=20261006-layouts1';
import { validateLayouts, drawLayoutInformation } from '../preview/layout-core.js?v=20261012-activity1';
import { resource, decodeJSON, loadClip, frameGeometry } from '../size-review/render-core.js?v=20261008-acceptance2';

const $ = selector => document.querySelector(selector), repo = new URL('../', import.meta.url), cache = new Map();
const policy = new AftercarePolicy(), reduced = matchMedia('(prefers-reduced-motion: reduce)');
const endings = [
  { variant: 'towel', title: '擦擦汗', id: 'sport-towel-first-20261012', note: '背心 + 毛巾 · 舊候選', defect: '擦拭中有近似幀，轉換仍偏跳；頭身比例偏長，待重畫。' },
  { variant: 'drink', title: '喝一口水', id: null, note: '12 格新稿待修', defect: '水壺換手待修；新稿 12 格仍未通過，暫不播放。' },
  { variant: 'rest', title: '鬆開外套', id: 'fitness-tracksuit-first-20261012', note: '酒紅外套 + 耳機 · 舊候選', defect: '開外套與呼氣仍有跳格，末格停在開襟姿勢，待補銜接。' }
];
let catalog, layouts, selected = 'towel', layoutID = 'classic', frame = 0, raf = null, offerTimer = null, offeredKey = null, started = 0, playing = false, simulatedBackground = false, eventCounter = 0, lastEvent = null;
const state = { ready: false, selected, frame, playing, layoutID, clips: {}, geometry: null, policy: policy.state, drawnFrames: [], playbackCount: 0, error: null };
window.__patrickAftercare = state;
const current = () => endings.find(ending => ending.variant === selected), currentClip = () => current()?.clip;
const variants = () => endings.filter(ending => ending.clip).map(ending => ending.variant);
const active = () => !document.hidden && !simulatedBackground;
const quiet = () => $('#quiet').checked || reduced.matches;
const text = (tag, content, className) => { const node = document.createElement(tag); node.textContent = content; if (className) node.className = className; return node; };

function stopPlayback(message) {
  if (raf !== null) cancelAnimationFrame(raf);
  raf = null; playing = false; state.playing = false;
  if (message) $('#playback-status').textContent = message;
}
function syncPolicy() {
  const value = policy.state; state.policy = value;
  if (value.phase === 'offered' && offeredKey !== value.eventID) {
    clearTimeout(offerTimer); offeredKey = value.eventID;
    offerTimer = setTimeout(() => { policy.tick(Date.now()); syncPolicy(); }, Math.max(1, 60001 - (Date.now() - value.offeredAtMS)));
  } else if (value.phase !== 'offered') { clearTimeout(offerTimer); offerTimer = null; offeredKey = null; }
  if (playing && value.phase !== 'playing') stopPlayback('演出已停止；回到前景也不會自動接著播。');
  const labels = { idle: '尚未觸發', offered: '等待你的選擇', playing: '演出一次', done: '本次已結束', dismissed: '本次已略過' };
  $('#phase-pill').textContent = labels[value.phase] || value.phase;
  const details = {
    idle: ['要看時，再叫派大星。', '頁面打開時不自動播，也不補播先前結束的動作。'],
    offered: ['這次想用哪個結尾？', '選好右上方的候選，再點「演這個結尾」。也可以略過。'],
    playing: ['派大星正在收尾。', '只是候選動畫試演，沒有更新運動、健康或日常造型。'],
    done: ['好，這段就到這裡。', '同一完成事件不再重播；要再審稿，可手動按「播放候選」。'],
    dismissed: ['留一點安靜的空間。', '離開、減少動態或開始新倒數會中止本次；不回頭補播。']
  };
  const copy = details[value.phase] || details.idle;
  $('#offer-title').textContent = copy[0]; $('#offer-detail').textContent = copy[1];
  $('#event-log').textContent = `${value.mode === 'review' ? '手動審稿' : '合成事件試演'}${value.eventID ? ` · ${value.eventID}` : ''}${value.reason ? ` · ${value.reason}` : ''}`;
  const canPlay = state.ready && !!currentClip() && active() && !quiet();
  $('#play-review').disabled = !canPlay || playing;
  $('#accept-ending').disabled = !canPlay || value.phase !== 'offered';
  $('#dismiss').disabled = !['offered', 'playing'].includes(value.phase);
  $('#stop').disabled = !playing;
  $('#simulate-complete').disabled = !state.ready || !active() || quiet();
  $('#new-timer').disabled = !state.ready;
  $('#replay-event').disabled = !lastEvent;
  $('#frame').disabled = !currentClip(); $('#previous-frame').disabled = !currentClip() || frame <= 0;
  $('#next-frame').disabled = !currentClip() || frame >= (currentClip()?.frameCount || 1) - 1;
}
function updateVisibility() {
  policy.updateVisibility({ active: active(), lowPower: false, reduceMotion: quiet(), nowMS: Date.now() }); syncPolicy();
  if (!active() || quiet()) stopPlayback('已停止動作；逐幀檢查仍可使用。重新開啟播放需要再按一次。');
}
function draw() {
  const clip = currentClip(); if (!clip) return;
  const layout = layouts.find(value => value.id === layoutID), geometry = frameGeometry(clip, frame, catalog.master, layout);
  for (const canvas of [$('#large-watch'), $('#small-watch')]) {
    const context = canvas.getContext('2d'); context.clearRect(0, 0, 832, 992); context.fillStyle = '#091c20'; context.fillRect(0, 0, 832, 992);
    context.drawImage(geometry.source, 0, 0, geometry.source.width, geometry.source.height, ...geometry.rect);
    context.textAlign = 'center'; context.textBaseline = 'middle'; context.fillStyle = '#fff9e9'; context.font = `${layout.id === 'bold' ? 600 : 480} ${layout.timeFontSize}px "Segoe UI",sans-serif`; context.fillText('18:42', ...layout.timeCenter);
    context.fillStyle = '#b8cfbf'; context.font = `${layout.dateFontSize}px "Microsoft JhengHei",sans-serif`; context.fillText('週二 13 · 收操試演', ...layout.dateCenter);
    drawLayoutInformation(context, layout, { title: '運動倒數', countdown: '00:00', state: '合成完成事件', progress: 1 });
    canvas.dataset.frame = frame; canvas.dataset.sourceFrame = geometry.sourceIndex; canvas.dataset.clip = clip.id; canvas.dataset.layout = layoutID;
    canvas.dataset.pixelScale = geometry.pixelScale; canvas.dataset.rect = JSON.stringify(geometry.rect); canvas.dataset.bounds = JSON.stringify(geometry.bounds);
  }
  state.frame = frame; state.layoutID = layoutID; state.selected = selected;
  state.geometry = { rect: geometry.rect, bounds: geometry.bounds, anchor: geometry.anchor, pixelScale: geometry.pixelScale, sourceIndex: geometry.sourceIndex };
  $('#frame').value = frame; $('#frame').max = clip.frameCount - 1; $('#frame-label').textContent = `${frame + 1} / ${clip.frameCount}`;
  if (playing && state.drawnFrames.at(-1) !== frame) state.drawnFrames.push(frame);
  syncPolicy();
}
function selectEnding(variant) {
  if (!endings.find(ending => ending.variant === variant)?.clip) return;
  if (playing) { policy.dismiss(); stopPlayback('已換到另一個獨立結尾，請手動播放。'); }
  selected = variant; frame = 0;
  document.querySelectorAll('[data-variant]').forEach(node => node.setAttribute('aria-pressed', String(node.dataset.variant === selected)));
  const ending = current(), clip = ending.clip;
  $('#clip-facts').replaceChildren(text('strong', `${clip.frameCount} 格 · ${(clip.totalMs / 1000).toFixed(2)} 秒 · 固定整段倍率`), text('p', ending.defect, 'defect'), text('small', `來源：${clip.id} · 尚未通過美術確認`), text('small', `PNG SHA ${clip.sha256}`), text('small', `輪廓 SHA ${clip.frameRegions.sha256}`));
  const link = new URL('../size-review/', import.meta.url); link.search = new URLSearchParams({ review: 'candidates', left: 'exercise', right: clip.id }); $('#review-link').href = link.href;
  $('#playback-status').textContent = `已載入「${ending.title}」。按播放才會演出；可先逐幀看比例和裁切。`; draw();
}
function play(review = false) {
  if (!currentClip() || !active() || quiet()) return;
  if (review) policy.beginReview({ kind: 'exercise', nowMS: Date.now(), availableVariants: variants() });
  policy.choose(selected, Date.now()); syncPolicy();
  if (policy.state.phase !== 'playing') return;
  frame = 0; started = performance.now(); playing = true; state.playing = true; state.playbackCount++; state.drawnFrames = []; draw();
  $('#playback-status').textContent = `正在以 1× 播放「${current().title}」；只播一次。`;
  const tick = now => {
    policy.tick(Date.now()); syncPolicy(); if (!playing) return;
    const elapsed = now - started; frame = frameAt(currentClip(), elapsed); draw();
    if (elapsed >= currentClip().totalMs) { policy.finish(Date.now()); stopPlayback('這段已播完，停在末格。再播需手動按一次。'); syncPolicy(); }
    else raf = requestAnimationFrame(tick);
  }; raf = requestAnimationFrame(tick);
}
function manualFrame(value) { if (playing) policy.dismiss(); stopPlayback('逐幀檢查中；沒有改變每格縮放。'); frame = Math.max(0, Math.min(currentClip().frameCount - 1, value)); draw(); }

$('#play-review').addEventListener('click', () => play(true)); $('#accept-ending').addEventListener('click', () => play(false));
$('#stop').addEventListener('click', () => { policy.dismiss(); stopPlayback('已手動停止；不自動續播。'); syncPolicy(); });
$('#frame').addEventListener('input', event => manualFrame(Number(event.target.value)));
$('#previous-frame').addEventListener('click', () => manualFrame(frame - 1)); $('#next-frame').addEventListener('click', () => manualFrame(frame + 1));
$('#layout').addEventListener('change', event => { layoutID = event.target.value; draw(); });
$('#simulate-complete').addEventListener('click', () => {
  const nowMS = Date.now(), id = `synthetic-exercise-${++eventCounter}`;
  policy.observeActivity({ id, kind: 'exercise', status: 'running', nowMS });
  lastEvent = { id, kind: 'exercise', status: 'completed', endedAtMS: nowMS };
  policy.receiveCompletion(lastEvent, { nowMS, availableVariants: variants() }); syncPolicy();
});
$('#replay-event').addEventListener('click', () => { if (lastEvent) policy.receiveCompletion(lastEvent, { nowMS: Date.now(), availableVariants: variants() }); syncPolicy(); });
$('#new-timer').addEventListener('click', () => { policy.observeActivity({ id: `synthetic-next-${++eventCounter}`, kind: 'exercise', status: 'running', nowMS: Date.now() }); syncPolicy(); });
$('#dismiss').addEventListener('click', () => { policy.dismiss(); syncPolicy(); });
$('#quiet').addEventListener('change', updateVisibility);
$('#background').addEventListener('click', () => { simulatedBackground = !simulatedBackground; $('#background').textContent = simulatedBackground ? '模擬回到前景' : '模擬退到背景'; updateVisibility(); });
document.addEventListener('visibilitychange', updateVisibility); reduced.addEventListener('change', updateVisibility);
// Repaint the current (unchanged) frame after the two viewports reflow. Some
// Chromium compositors discard an off-screen canvas surface during a resize.
// This is not a playback restart and does not advance the frame or policy.
window.addEventListener('resize', () => requestAnimationFrame(() => { if (state.ready && currentClip()) draw(); }));

try {
  const [candidateBytes, layoutBytes] = await Promise.all([resource('animation/candidates.json', repo), resource('experience/layouts.json', repo)]);
  catalog = decodeJSON(candidateBytes); layouts = validateLayouts(decodeJSON(layoutBytes));
  for (const layout of layouts) { const option = text('option', layout.title); option.value = layout.id; $('#layout').append(option); }
  await Promise.all(endings.filter(ending => ending.id).map(async ending => {
    try { const raw = catalog.clips.find(clip => clip.id === ending.id); if (!raw) throw new Error('目錄缺少這組候選'); ending.clip = await loadClip(raw, repo, cache); if (!ending.clip.available) throw new Error('候選來源尚未備妥'); state.clips[ending.variant] = { id: ending.clip.id, frames: ending.clip.frameCount, totalMs: ending.clip.totalMs, scale: ending.clip.scale, sha256: ending.clip.sha256, regionsSha256: ending.clip.frameRegions.sha256 }; }
    catch (error) { ending.clip = null; ending.note = '載入未完成'; ending.defect = error.message; }
  }));
  endings.forEach((ending, index) => { const button = text('button', '', 'ending'); button.dataset.variant = ending.variant; button.setAttribute('aria-pressed', 'false'); button.disabled = !ending.clip; const copy = document.createElement('span'); copy.append(text('strong', ending.title), text('small', ending.clip ? ending.note : ending.defect)); button.append(text('span', String(index + 1).padStart(2, '0'), 'number'), copy); button.addEventListener('click', () => selectEnding(ending.variant)); $('#endings').append(button); });
  state.ready = true; document.documentElement.dataset.aftercare = 'ready'; updateVisibility();
  const first = endings.find(ending => ending.clip); if (first) selectEnding(first.variant); else throw new Error('目前沒有可播放的候選來源');
} catch (error) { state.error = error.message; document.documentElement.dataset.aftercare = 'error'; $('#playback-status').textContent = `載入失敗：${error.message}。請重新整理或回原有審稿頁。`; }
