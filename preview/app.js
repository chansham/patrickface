import { STAGE, normalizeClip, sourceRect, destinationRect, validateFrameRegions, frameAt, isIdleClip, IdleScheduler, restoreEvents, bedtimeRemaining, automaticAllowed, reviewKey, cleanReview } from './player-core.js?v=20261006-layouts1';
import { newPet, restorePet, dispatch, resolveScene, MOODS } from './pet-core.js?v=20261006-layouts1';
import { createExperience } from './experience-ui.js?v=20261006-layouts1';
import { EXPERIENCE_KEY } from './experience-core.js?v=20261006-layouts1';
import { createClockRig } from './clock-rig.js?v=20261006-layouts1';
import { DEFAULT_LAYOUT, transformRect, applyLayoutDOM } from './layout-core.js?v=20261006-layouts1';

const $ = selector => document.querySelector(selector);
const shell = window.__patrickPreviewShell;
// Only this exact query value selects the separate, fixed candidate catalog.
const candidateMode = new URL(location.href).searchParams.get('review') === 'candidates';
const revision = `${shell.build}-${new URL(location.href).searchParams.get('retry') || '0'}`;
const repo = new URL('../', import.meta.url);
const keys = { settings: 'patrick.animation-player.v1', events: 'patrick.animation-events.v1', pet: 'patrick.pet.v1', experience: EXPERIENCE_KEY };
let experienceUI = null;
let faceLayout = DEFAULT_LAYOUT;
let storageAvailable = true;
function read(key) { try { return JSON.parse(localStorage.getItem(key)); } catch { storageAvailable = false; return null; } }
function write(key, value) {
  if (candidateMode && Object.values(keys).includes(key)) return false;
  try { localStorage.setItem(key, JSON.stringify(value)); return true; } catch { storageAvailable = false; return false; }
}
const reviewStorageKey = clip => candidateMode ? reviewKey(clip).replace('patrick.animation-review.', 'patrick.animation-candidate-review.') : reviewKey(clip);
const sceneNames = { auto: '跟著時間', sleeping: '睡前', awake: '日常', charging: '充電', exercise: '運動', focus: '專心', bath: '洗澡', celebrate: '節日' };
const settings = candidateMode ? {} : read(keys.settings) || {};
const events = restoreEvents(candidateMode ? null : read(keys.events));
let pet = candidateMode ? newPet() : restorePet(read(keys.pet) || newPet());
let noCatchupBefore = Date.now();
const state = { clip: null, frame: 0, playing: false, kind: null, elapsed: 0, raf: null, last: 0,
  scene: Object.hasOwn(sceneNames, settings.scene) ? settings.scene : candidateMode ? 'sleeping' : 'auto', reviewing: candidateMode,
  enabled: !candidateMode && settings.enabled !== false, wristDown: false, lowPower: false, scope: 'action', sceneDate: '', entryNotice: '' };
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const idle = new IdleScheduler();
const canvases = [$('#face'), $('#wrist-face')];
const contexts = canvases.map(canvas => canvas.getContext('2d'));
if (contexts.some(context => !context)) throw new Error('瀏覽器無法顯示畫稿');
const images = new Map(), frameCanvases = new Map(), reviews = new Map();
let buttons = [];
const catalogPath = candidateMode ? 'animation/candidates.json' : 'animation/catalog.json';
const catalogURL = new URL(catalogPath, repo); catalogURL.searchParams.set('v', revision);
shell.report.mode = candidateMode ? 'candidates' : 'main'; shell.report.catalog = catalogPath;
if (candidateMode) {
  $('.intro .eyebrow').textContent = '待修候選 / 逐格審稿';
  $('.intro h1').textContent = '先把問題看清楚。';
  $('#intro-description').textContent = '查看已生成、尚未通過檢查的畫稿，指出哪一格需要怎麼改。';
  $('.scope p:last-child').textContent = '保留已知瑕疵供審稿。此頁不觸發生活事件，也不更新主預覽的陪伴設定或計時。';
  $('footer').textContent = '候選意見與主預覽分開保存 · 畫格原尺寸與問題保持可見';
  for (const selector of ['.scene-picker', '.interactions', '.idle-control', '.settings']) $(selector).hidden = true;
}
const response = await fetch(catalogURL, { cache: 'no-store', signal: AbortSignal.timeout(10000) });
if (!response.ok) throw new Error(`動作目錄 HTTP ${response.status}`);
const catalog = await response.json();
if (catalog.version !== 1 || !Array.isArray(catalog.clips) || !catalog.clips.length) throw new Error('動作目錄沒有可讀取的 clips');
const clips = catalog.clips.map(normalizeClip);
if (new Set(clips.map(clip => clip.id)).size !== clips.length) throw new Error('動作目錄有重複識別碼');
const candidateFilters = { all: '全部', new: '本批新增', idle: '待機', interaction: '互動', scene: '生活情境' };
const latestBatch = [...new Set(clips.map(clip => clip.batch).filter(batch => typeof batch === 'string' && batch))]
  .sort((a, b) => a.localeCompare(b, 'en', { numeric: true })).at(-1);
let candidateFilter = 'all', matchingClips = clips;
function reviewGroup(clip) {
  if (['idle', 'interaction', 'scene'].includes(clip.reviewGroup)) return clip.reviewGroup;
  if (isIdleClip(clip) || ['待機', 'idle'].includes(clip.category)) return 'idle';
  if (['互動', 'interaction'].includes(clip.category) || clip.triggerKinds.includes('interaction')) return 'interaction';
  return 'scene';
}
function matchesCandidate(clip, filter) {
  return filter === 'all' || (filter === 'new' ? Boolean(latestBatch && clip.batch === latestBatch) : reviewGroup(clip) === filter);
}

const digestHex = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), value => value.toString(16).padStart(2, '0')).join('');
async function loadRegions(clip, atlas) {
  const reference = clip.frameRegions;
  if (reference.version !== 1 || typeof reference.path !== 'string' || !/^[a-f0-9]{64}$/i.test(reference.sha256 || '')) throw new Error('輪廓資料索引無效');
  const url = new URL(reference.path, repo);
  if (url.origin !== repo.origin || !url.pathname.startsWith(repo.pathname)) throw new Error('輪廓資料路徑不在這個專案');
  url.searchParams.set('v', `${revision}-${reference.sha256}`);
  const response = await fetch(url, { signal: AbortSignal.timeout(10000), cache: 'no-store' });
  if (!response.ok) throw new Error(`輪廓資料 HTTP ${response.status}`);
  const bytes = await response.arrayBuffer(), hash = await digestHex(bytes);
  if (hash !== reference.sha256.toLowerCase()) throw new Error('輪廓資料校驗不符，請重新載入');
  const metadata = validateFrameRegions(clip, JSON.parse(new TextDecoder().decode(bytes).replace(/^\uFEFF/, '')));
  const frames = metadata.frames.map((frame, index) => {
    const canvas = document.createElement('canvas'); canvas.width = metadata.canvas.width; canvas.height = metadata.canvas.height;
    canvas.dataset.regionClip = clip.id; canvas.dataset.sourceFrame = String(index);
    const context = canvas.getContext('2d');
    if (!context) throw new Error('瀏覽器無法建立輪廓畫布');
    const [dx, dy] = frame.translation;
    // Mask in the original pixel grid. No bounding-box fitting or resampling:
    // every atlas pixel is translated by one integer offset onto one common canvas.
    context.imageSmoothingEnabled = false; context.save(); context.beginPath();
    for (const [y, ...runs] of frame.rows) for (let i = 0; i < runs.length; i += 2) {
      context.rect(runs[i] + dx, y + dy, runs[i + 1] - runs[i], 1);
    }
    context.clip(); context.drawImage(atlas, dx, dy); context.restore();
    return canvas;
  });
  clip.renderCanvas = metadata.canvas; clip.regionsMetadata = metadata;
  clip.currentRendering = { method: 'contour-runs', renderingRevision: reference.version, regionsHash: hash,
    sourceImageHash: clip.sha256, canvas: metadata.canvas, singleScale: 1 };
  frameCanvases.set(clip.id, frames);
}

async function loadClip(clip) {
  if (!clip.available) return;
  try {
    const url = new URL(clip.atlas, repo);
    if (url.origin !== repo.origin || !url.pathname.startsWith(repo.pathname)) throw new Error('畫稿路徑不在這個專案');
    url.searchParams.set('v', `${revision}-${clip.version}-${clip.sha256 || ''}`);
    const result = await fetch(url, { signal: AbortSignal.timeout(10000), cache: 'no-store' });
    if (!result.ok) throw new Error(`畫稿 HTTP ${result.status}`);
    const bytes = await result.arrayBuffer();
    const hash = await digestHex(bytes);
    if (clip.sha256 && hash !== clip.sha256.toLowerCase()) throw new Error('畫稿版本校驗不符，請重新載入');
    clip.sha256 = hash;
    const blobURL = URL.createObjectURL(new Blob([bytes], { type: 'image/png' }));
    const image = new Image();
    try {
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('畫稿解碼超時')), 10000);
        image.onload = () => { clearTimeout(timeout); resolve(); };
        image.onerror = () => { clearTimeout(timeout); reject(new Error('畫稿無法解碼')); };
        image.src = blobURL;
      });
      if (image.naturalWidth !== clip.width || image.naturalHeight !== clip.height) throw new Error('畫稿尺寸與分格資料不符');
      if (clip.frameRegions) await loadRegions(clip, image);
      else clip.currentRendering = { method: 'regular-grid', renderingRevision: 'legacy-grid-v1', regionsHash: null, sourceImageHash: clip.sha256 };
      images.set(clip.id, image);
    } finally { URL.revokeObjectURL(blobURL); }
  } catch (error) {
    clip.available = false; clip.loadError = String(error.message || error); clip.unavailableReason = clip.loadError;
  }
}
await Promise.all(clips.map(loadClip));
if (!images.size) throw new Error(clips.find(clip => clip.loadError)?.loadError || '動作畫稿尚未提供');
shell.report.clipsLoaded = [...images.keys()];
shell.report.clipsFailed = clips.filter(clip => clip.loadError).map(clip => ({ id: clip.id, error: clip.loadError }));
shell.report.rendering = Object.fromEntries(clips.filter(clip => clip.available).map(clip => [clip.id, clip.currentRendering]));
$('#catalog-summary').textContent = candidateMode
  ? `目前可審稿 ${images.size} 組：${clips.filter(clip => clip.available).map(clip => clip.title).join('、')}。`
  : `目前可試 ${images.size} 組：${clips.filter(clip => clip.available).map(clip => clip.title).join('、')}。其餘情境在選取時標示待補。`;
function populateClipOptions(list) {
  $('#clip-select').replaceChildren();
  for (const clip of list) {
    const option = document.createElement('option'); option.value = clip.id;
    option.textContent = `${clip.title}${clip.available ? '' : clip.loadError ? ' · 載入失敗' : ' · 待補'}`;
    $('#clip-select').append(option);
  }
}
populateClipOptions(clips);
if (candidateMode) {
  $('#candidate-filters').hidden = false;
  for (const [filter, title] of Object.entries(candidateFilters)) {
    const button = document.createElement('button'); button.type = 'button'; button.dataset.candidateFilter = filter;
    button.textContent = `${title} · ${clips.filter(clip => matchesCandidate(clip, filter)).length}`;
    button.setAttribute('aria-pressed', String(filter === candidateFilter));
    button.addEventListener('click', () => applyCandidateFilter(filter)); $('#candidate-filter-buttons').append(button);
  }
  $('#candidate-filter-summary').textContent = `全部 ${clips.length} 組。所有分類都手動播一次；待機畫稿不會在這裡自動觸發。`;
}

function applyCandidateFilter(filter) {
  if (!candidateMode || !Object.hasOwn(candidateFilters, filter)) return;
  holdReview(); candidateFilter = filter; matchingClips = clips.filter(clip => matchesCandidate(clip, filter));
  // Filtering an empty group leaves the current frame and unsent review intact.
  // Otherwise keep the selected clip/frame when it belongs to the new group.
  const next = matchingClips.find(clip => clip.id === state.clip?.id) || matchingClips[0];
  populateClipOptions(matchingClips.length ? matchingClips : state.clip ? [state.clip] : []);
  if (next && next !== state.clip) selectClip(next, true);
  else if (state.clip) $('#clip-select').value = state.clip.id;
  document.querySelectorAll('[data-candidate-filter]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.candidateFilter === filter)));
  $('#candidate-filter-summary').textContent = matchingClips.length
    ? `${candidateFilters[filter]} ${matchingClips.length} 組。所有分類都手動播一次；待機畫稿不會在這裡自動觸發。`
    : `${candidateFilters[filter]}目前沒有畫稿，保留正在查看的這一格。其他分類的意見不受影響。`;
  controls();
}

function saveSettings() { if (!candidateMode) write(keys.settings, { version: 1, scene: state.scene, enabled: state.enabled }); }
function savePet(event) { if (candidateMode) return; pet = dispatch(pet, event, Date.now()); write(keys.pet, pet); updateCompanion(); }
function blocked() { return reduced.matches || state.wristDown || state.lowPower; }
function context() { return { enabled: state.enabled && shell.report.status === 'ready', reduced: reduced.matches, wristDown: state.wristDown,
  lowPower: state.lowPower, hidden: document.hidden, reviewing: state.reviewing }; }
function sceneClips(scene = state.scene) { return clips.filter(clip => clip.scenes.includes(scene === 'auto' ? experienceUI?.resolvedScene() || 'awake' : scene)); }
function idleClips() { return experienceUI ? experienceUI.idleClips() : sceneClips().filter(clip => clip.available && isIdleClip(clip)); }
function currentReview() { return state.clip?.available ? reviewFor(state.clip) : null; }
function reviewFor(clip) {
  if (!reviews.has(clip.id)) {
    let raw = read(reviewStorageKey(clip));
    if (!candidateMode && !raw) raw = read(`patrick.animation-review.${clip.id}.v${clip.version}`);
    if (!candidateMode && !raw && clip.id === 'yawn') raw = read(`patrick.animation-review.patrick-bedtime-yawn-v1.v${clip.version}`);
    reviews.set(clip.id, cleanReview(raw, clip));
  }
  return reviews.get(clip.id);
}
function section() { return currentReview()?.sections[state.scope]; }
function saveReview() {
  const review = currentReview(); if (!review) return;
  review.updatedAt = new Date().toISOString();
  $('#save-status').textContent = write(reviewStorageKey(state.clip), review) ? '已儲存在這個瀏覽器。' : '本機儲存不可用，請匯出意見留存。';
}
function drawCell(context, clip, index, rectangle) {
  const source = clip.frameRegions ? frameCanvases.get(clip.id)?.[clip.frameIndices[index]] : images.get(clip.id);
  if (!source) throw new Error(`${clip.title}：這一格尚未完成輪廓載入`);
  context.drawImage(source, ...sourceRect(clip, index), ...rectangle);
}
function display(index) {
  const clip = state.clip;
  state.frame = index;
  for (let i = 0; i < contexts.length; i++) {
    contexts[i].clearRect(0, 0, STAGE.width, STAGE.height);
    if (clip?.available) drawCell(contexts[i], clip, index, transformRect(destinationRect(clip, catalog.master), faceLayout));
    canvases[i].dataset.frame = String(index); canvases[i].dataset.clip = clip?.id || '';
  }
  shell.report.frames++; shell.report.currentClip = clip?.id; shell.report.currentFrame = index;
  $('#frame-count').textContent = clip?.available ? `${String(index + 1).padStart(2, '0')} / ${String(clip.frameCount).padStart(2, '0')}` : '畫稿待補';
  $('#review-frame').textContent = String(index + 1);
  $('#verdict').value = section()?.frames[index] || '';
  buttons.forEach((button, i) => { button.setAttribute('aria-pressed', String(i === index)); button.dataset.verdict = section()?.frames[i] || ''; });
  const sourceIndex = clip?.frameIndices?.[index];
  $('#status').textContent = !clip?.available ? (clip?.unavailableReason || '這組動作畫稿待補。')
    : clip.frameLabels[index] || clip.frameLabels[sourceIndex] || `${clip.title}${experienceUI ? '' : ` · 第 ${index + 1} 格`}`;
  $('#previous-frame').disabled = !clip?.available || index === 0;
  $('#next-frame').disabled = !clip?.available || index >= clip.frameCount - 1;
  experienceUI?.frameChanged();
}
function reviewUI() {
  $('#review-note').value = section()?.note || '';
  $('#review-revision').textContent = state.clip?.available ? `${state.clip.id} · v${state.clip.version} · SHA-256 ${state.clip.sha256.slice(0, 16)}…${state.clip.renderCanvas ? ' · 取圖方式已更新，既有意見保留。' : ''}` : '有畫稿後才能對這一版留意見。';
  $('#review-prompt').textContent = state.scope === 'action' ? '看表情、姿勢、節奏和收尾。' : '看服裝、配色、配件和細節的一致性。';
  document.querySelectorAll('[data-review-scope]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.reviewScope === state.scope)));
  if (!storageAvailable) $('#save-status').textContent = '本機儲存不可用，請匯出意見留存。';
}
function controls() {
  const available = Boolean(state.clip?.available);
  $('#clip-select').disabled = candidateMode && !matchingClips.length;
  $('#pause').disabled = !state.playing;
  for (const id of ['play', 'speed', 'verdict', 'review-note']) $(`#${id}`).disabled = !available;
  $('#verdict').disabled ||= state.playing;
  $('#play').textContent = blocked() ? '逐格看動作 →' : state.playing ? '從頭播放 ↗' : experienceUI && !state.reviewing ? '演一下 ↗' : '播放一次 ↗';
  $('#reduced-note').hidden = !blocked();
  $('#resume-idle').hidden = candidateMode || !state.reviewing;
  $('#play-hint').textContent = candidateMode ? '手動播一次，或點任一格停住比較；播放結束後不循環。'
    : state.reviewing ? '正在看稿：自動待機已暫停，完成後按「繼續日常陪伴」。' : '每段演完就停。摸摸頭和投餵會優先播放，不排隊補演。';
  $('#face').setAttribute('aria-label', experienceUI && !state.reviewing ? '摸摸頭' : blocked() ? '下一格動作畫稿' : `播放${state.clip?.title || '目前動作'}一次`);
  shell.report.playing = state.playing; shell.report.playKind = state.kind; shell.report.reviewing = state.reviewing;
  for (const id of ['pet', 'feed']) {
    const found = clips.find(clip => clip.id === id);
    $(`#${id}`).disabled = experienceUI ? false : !found?.available;
    $(`#${id}`).textContent = `${id === 'pet' ? '摸摸頭' : '餵一口'}${experienceUI || found?.available ? '' : ' · 待補'}`;
  }
  if (candidateMode) for (const selector of ['.scene-picker', '.interactions', '.idle-control', '.settings']) {
    $(selector).querySelectorAll('button,input,select').forEach(control => { control.disabled = true; });
  }
  updateIdleStatus();
}
function pause() {
  state.playing = false; state.kind = null; cancelAnimationFrame(state.raf); state.raf = null; idle.reset(); controls();
}
function holdReview() { pause(); state.reviewing = true; idle.reset(); controls(); }
function selectClip(clip, reviewMode = false) {
  pause(); if (reviewMode) state.reviewing = true;
  state.clip = clip; state.elapsed = 0;
  $('#clip-select').value = clip.id; $('#clip-title').textContent = clip.title;
  $('#clip-state').textContent = experienceUI ? `${sceneNames[experienceUI.resolvedScene()] || '日常'}陪伴` : clip.available ? `${clip.frameCount} 格 · ${clip.renderCanvas ? '輪廓分離・固定腳底' : candidateMode ? '待修候選' : isIdleClip(clip) ? '待機動作' : '單次情境'}` : clip.loadError ? '載入失敗' : '畫稿待補';
  $('#clip-description').textContent = candidateMode ? `已知問題：${clip.description || '待逐格檢查，尚未完成品質驗收。'}` : clip.description || '每段動作由獨立畫格組成。';
  $('#frames').replaceChildren(); buttons = [];
  if (clip.available) buttons = Array.from({ length: clip.frameCount }, (_, index) => {
    const button = document.createElement('button'); button.className = 'frame'; button.type = 'button';
    button.setAttribute('aria-label', `第 ${index + 1} 格：${clip.frameLabels[index] || clip.title}`);
    const thumb = document.createElement('canvas'); thumb.width = 144; thumb.height = 144; thumb.setAttribute('aria-hidden', 'true');
    // The same common frame canvas serves both watches and every thumbnail.
    const cellAspect = clip.renderCanvas ? clip.renderCanvas.width / clip.renderCanvas.height
      : (clip.width / clip.columns) / (clip.height / clip.rows);
    const tw = 144 * Math.min(1, cellAspect), th = 144 * Math.min(1, 1 / cellAspect);
    drawCell(thumb.getContext('2d'), clip, index, [(144 - tw) / 2, (144 - th) / 2, tw, th]);
    const number = document.createElement('span'); number.textContent = String(index + 1).padStart(2, '0'); button.append(thumb, number);
    button.addEventListener('click', () => selectFrame(index));
    button.addEventListener('keydown', event => { if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); selectFrame(index + (event.key === 'ArrowRight' ? 1 : -1)); buttons[state.frame].focus(); } });
    $('#frames').append(button); return button;
  });
  $('#progress').value = 0; reviewUI(); display(0); controls();
}
function selectFrame(index) {
  if (!state.clip?.available) return;
  holdReview(); const next = Math.max(0, Math.min(state.clip.frameCount - 1, index));
  state.elapsed = next === 0 ? 0 : state.clip.ends[next - 1]; display(next); $('#progress').value = state.elapsed / state.clip.totalMs;
}
function tick(now) {
  if (!state.playing) return;
  if (document.hidden || blocked()) { pause(); return; }
  try {
    const clip = state.clip;
    const speed = state.kind === 'review' ? Number($('#speed').value) : 1;
    state.elapsed = Math.min(clip.totalMs, state.elapsed + Math.max(0, now - state.last) * speed); state.last = now;
    const index = frameAt(clip, state.elapsed); if (index !== state.frame) display(index);
    $('#progress').value = state.elapsed / clip.totalMs;
    if (state.elapsed >= clip.totalMs) {
      display(clip.frameCount - 1); pause(); $('#status').textContent = `${clip.title}演完了，安靜歇一下。`; return;
    }
    state.raf = requestAnimationFrame(tick);
  } catch (error) { pause(); shell.fail(error); }
}
function playClip(clip, kind = 'interaction') {
  if (candidateMode && kind !== 'review') return false;
  if (!clip?.available || document.hidden || shell.report.status !== 'ready') return false;
  if (blocked()) {
    selectClip(clip, true); selectFrame(Math.min(1, clip.frameCount - 1)); return false;
  }
  selectClip(clip, kind === 'review'); state.elapsed = 0; state.playing = true; state.kind = kind;
  state.last = performance.now(); idle.reset(); controls(); state.raf = requestAnimationFrame(tick); return true;
}
function playSelected() {
  if (!state.clip?.available) return;
  if (blocked()) { selectFrame((state.frame + 1) % state.clip.frameCount); return; }
  playClip(state.clip, experienceUI && !state.reviewing ? 'interaction' : 'review');
}
function sceneDefault() {
  if (experienceUI) return experienceUI.defaultClip();
  const expected = { sleeping: 'yawn', awake: 'idle-blink-normal', charging: 'charging', exercise: 'exercise', focus: 'focus', bath: 'bath', celebrate: 'celebrate' }[state.scene];
  return clips.find(clip => clip.id === expected) || sceneClips().find(clip => !isIdleClip(clip)) || sceneClips()[0];
}
function updateSceneText() {
  if (experienceUI) {
    $('#scene-explanation').textContent = state.scene === 'auto' ? `現在是${sceneNames[experienceUI.resolvedScene()] || '日常'}時間。自己選的衣服會保留，選「跟著情境」才會自動換裝。`
      : `${sceneNames[state.scene]}情境已選好。想互動就摸摸頭或餵一口。${state.entryNotice ? ` ${state.entryNotice}` : ''}`;
    $('#missing-actions').hidden = true; return;
  }
  const named = sceneNames[state.scene];
  const explanation = state.scene === 'sleeping'
    ? '進入睡前時打一次哈欠；10 分鐘內再進來不重播。待機眨眼是另外的小動作。'
    : state.scene === 'awake' ? '正常、慢慢眨眼與雙眨是獨立待機動作，間隔 10–22 秒，不連續重複同一款。'
    : `${named}是手動情境；選好後按「播放一次」看這段表演。待機動作仍各自留有間隔。`;
  $('#scene-explanation').textContent = `${explanation}${state.entryNotice ? ` ${state.entryNotice}` : ''}`;
  const missing = sceneClips().filter(clip => !clip.available).map(clip => `${clip.title}${clip.loadError ? '（載入失敗，可重試）' : '（待補）'}`);
  $('#missing-actions').hidden = !missing.length && sceneClips().length > 0;
  $('#missing-actions').textContent = missing.length ? `這個情境尚缺：${missing.join('、')}` : '這個情境的動作尚未提供；會保留待補標記。';
}
function applyScene(value, entry = true) {
  if (candidateMode) return;
  experienceUI?.prepareScene();
  const changed = value !== state.scene; state.scene = value; state.reviewing = false; state.entryNotice = ''; idle.reset();
  $('#scene').value = value;
  if (entry) savePet({ type: 'mode', value: ({ exercise: 'stretching', bath: 'awake' })[value] || value });
  const clip = sceneDefault() || normalizeClip({ id: `pending-${value}`, title: `${sceneNames[value]}動作待補`, scenes: [value], description: '這個情境尚未有動作畫稿，不用其他動作替代。' });
  selectClip(clip);
  saveSettings();
  if (entry && changed && value === 'sleeping') {
    const remaining = bedtimeRemaining(events);
    if (remaining) state.entryNotice = `哈欠冷卻中，約 ${Math.ceil(remaining / 60000)} 分鐘後才會在下次進入時播放。`;
    else if (!automaticAllowed({ ...context(), enabled: true })) state.entryNotice = '這次進入維持安靜；恢復後不補播哈欠。';
    else if (playClip(experienceUI ? experienceUI.actionClip('yawn') : clips.find(clip => clip.id === 'yawn'), 'scene')) {
      events.bedtimeLastAt = Date.now(); write(keys.events, events); state.entryNotice = '剛進入睡前，這次只演一遍。';
    } else state.entryNotice = experienceUI ? '這套衣服先安靜陪你歇著。' : '睡前哈欠畫稿待補。';
  }
  experienceUI?.sceneChanged(entry);
  updateSceneText(); controls();
}
function updateIdleStatus() {
  let text;
  if (!state.enabled) text = '自動待機已關閉；仍可手動播放或逐格看。';
  else if (document.hidden || blocked()) text = '安靜模式：自動動作已停止，恢復後重新等待，不補播。';
  else if (state.reviewing) text = '正在審稿，自動動作不會打擾。';
  else if (state.playing) text = '這段演完後，才重新等下一次待機。';
  else if (!idleClips().length) text = experienceUI ? '這套衣服先安靜陪你；星星抱枕睡衣會偶爾眨眼。' : '這個情境還沒有待機畫稿，先安靜待著。';
  else if (idleClips().length === 1 && idleClips()[0].id === idle.lastId) text = '這個情境目前只有一款眨眼，已播過；等其他變化加入，不連續重播。';
  else text = `自動待機開啟 · ${idleClips().length} 款眨眼 · 每隔 10–22 秒出現一次。`;
  $('#idle-status').textContent = text;
  shell.report.idleNextAt = idle.nextAt; shell.report.idleLastId = idle.lastId;
}
function sceneDate() { return state.sceneDate ? new Date(`${state.sceneDate}T12:00:00`) : new Date(); }
function updateCompanion() {
  if (candidateMode) return;
  if (experienceUI) { experienceUI.heartbeat(); return; }
  const scene = resolveScene(pet, { now: Date.now(), reducedMotion: reduced.matches, alwaysOn: state.wristDown, lowBattery: state.lowPower }, sceneDate());
  $('#timer-status').textContent = scene.remaining ? `專心計時 ${Math.floor(scene.remaining / 60)}:${String(scene.remaining % 60).padStart(2, '0')}` : scene.activityComplete ? '這一段專心時間完成了。' : '沒有進行中的計時';
  $('#stop-timer').disabled = !pet.activity;
  $('#date-status').textContent = `${scene.holiday ? `情境日期：${scene.holiday.name}。` : '這個日期沒有已知節日。'}${pet.mood ? ` 今天記錄：${MOODS[pet.mood]}。` : ''} 數字時間、計時與冷卻仍按真實時間。`;
  if (scene.activityComplete && pet.activity && events.timerHandledAt !== pet.activity.endsAt) {
    events.timerHandledAt = pet.activity.endsAt; write(keys.events, events);
    if (pet.activity.endsAt > noCatchupBefore && automaticAllowed({ ...context(), enabled: true }) && !state.playing) playClip(clips.find(clip => clip.id === 'celebrate'), 'scene');
  }
}

$('#scene').addEventListener('change', event => applyScene(event.target.value));
$('#clip-select').addEventListener('change', event => selectClip(clips.find(clip => clip.id === event.target.value), true));
function activateFace(event) { return experienceUI && !state.reviewing ? experienceUI.petAction(event) : playSelected(); }
$('#play').addEventListener('click', playSelected); $('#face').addEventListener('click', activateFace);
$('#face').addEventListener('keydown', event => {
  if (['Enter', ' '].includes(event.key)) { event.preventDefault(); activateFace(event); }
  if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); selectFrame(state.frame + (event.key === 'ArrowRight' ? 1 : -1)); }
});
$('#pause').addEventListener('click', holdReview);
$('#previous-frame').addEventListener('click', () => selectFrame(state.frame - 1));
$('#next-frame').addEventListener('click', () => selectFrame(state.frame + 1));
$('#speed').addEventListener('change', holdReview);
$('#pet').addEventListener('click', event => { if (experienceUI) return experienceUI.petAction(event); savePet({ type: 'tap' }); playClip(clips.find(clip => clip.id === 'pet')); });
$('#feed').addEventListener('click', event => {
  if (experienceUI) return experienceUI.feedAction(event);
  savePet({ type: 'feed' });
  if (pet.lastEvent?.type === 'full') { $('#status').textContent = '剛吃過一口，歇三秒再餵。'; return; }
  playClip(clips.find(clip => clip.id === 'feed'));
});
$('#auto-idle').checked = state.enabled;
$('#auto-idle').addEventListener('change', event => { if (candidateMode) return; state.enabled = event.target.checked; idle.reset(); if (!state.enabled && state.kind === 'idle') pause(); saveSettings(); controls(); });
$('#resume-idle').addEventListener('click', () => { if (candidateMode) return; pause(); state.reviewing = false; idle.reset(); controls(); });
for (const [id, field] of [['wrist-down', 'wristDown'], ['low-power', 'lowPower']]) $(`#${id}`).addEventListener('change', event => { state[field] = event.target.checked; noCatchupBefore = Date.now(); pause(); idle.reset(); controls(); experienceUI?.quietChanged(); });
$('#show-guides').addEventListener('change', event => $('.viewports').classList.toggle('guides-off', !event.target.checked));
reduced.addEventListener('change', () => { noCatchupBefore = Date.now(); pause(); idle.reset(); controls(); experienceUI?.quietChanged(); });
document.addEventListener('visibilitychange', () => { noCatchupBefore = Date.now(); pause(); idle.reset(); controls(); experienceUI?.quietChanged(); });
$('#mood').value = pet.mood || '';
$('#mood').addEventListener('change', event => experienceUI ? experienceUI.moodChanged(event.target.value) : savePet({ type: 'mood', value: event.target.value }));
$('#focus-timer').addEventListener('click', event => { if (experienceUI) return experienceUI.focusTimer(event); applyScene('focus'); savePet({ type: 'timer', mode: 'focus', seconds: 1500 }); });
$('#stop-timer').addEventListener('click', () => experienceUI ? experienceUI.cancelTimer() : savePet({ type: 'stop' }));
$('#scene-date').addEventListener('change', event => { state.sceneDate = /^\d{4}-\d{2}-\d{2}$/.test(event.target.value) ? event.target.value : ''; updateCompanion(); const result = resolveScene(pet, { now: Date.now() }, sceneDate()); $('#date-status').textContent = result.holiday ? `${result.holiday.name}的小劇場日期；計時與數字時間仍照常。` : '這個日期沒有已知節日；計時與數字時間仍照常。'; experienceUI?.calendarMoment(result.holiday, true); });
for (const button of document.querySelectorAll('[data-review-scope]')) button.addEventListener('click', () => { holdReview(); state.scope = button.dataset.reviewScope; reviewUI(); display(state.frame); });
$('#review-note').addEventListener('focus', holdReview);
$('#review-note').addEventListener('input', event => { if (section()) { section().note = event.target.value; saveReview(); } });
$('#verdict').addEventListener('focus', holdReview);
$('#verdict').addEventListener('change', event => {
  if (!section()) return; holdReview();
  if (event.target.value) section().frames[state.frame] = event.target.value; else delete section().frames[state.frame];
  buttons[state.frame].dataset.verdict = event.target.value; saveReview();
});
$('#export-review').addEventListener('click', () => {
  holdReview();
  // Loading artwork and retrieving an existing review are independent. A
  // temporary 404 must not silently omit saved opinions from this export.
  const all = clips.filter(clip => /^[a-f0-9]{64}$/i.test(clip.sha256 || '') && Number.isInteger(clip.frameCount))
    .map(clip => ({ ...reviewFor(clip), title: clip.title, frameCount: clip.frameCount, imageAvailable: clip.available,
      currentRendering: clip.currentRendering || { method: 'unavailable', renderingRevision: null, regionsHash: clip.frameRegions?.sha256 || null },
      savedReviewRendering: reviewFor(clip).rendering ?? 'unknown',
      ...(candidateMode ? { qualityStatus: clip.status, knownProblems: clip.description || '' } : {}) }));
  const blob = new Blob([JSON.stringify({ schemaVersion: 2, type: 'animation-review', reviewMode: candidateMode ? 'candidates' : 'main', catalog: catalogPath, exportedAt: new Date().toISOString(), clips: all }, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob), link = document.createElement('a'); link.href = url; link.download = candidateMode ? 'patrick-animation-candidates-review.json' : 'patrick-animation-review.json'; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});

if (!candidateMode) experienceUI = await createExperience({ repo, revision, clips, read, write, getPet: () => pet, setPet: savePet, shell,
  player: { state, quiet: () => document.hidden || blocked(), noCatchupBefore: () => noCatchupBefore,
    setLayout(layout) { faceLayout = layout; applyLayoutDOM(layout); shell.report.layout = layout; if (state.clip) display(state.frame); },
    play: playClip, select: clip => selectClip(clip), hold: holdReview, changeScene: applyScene,
    resume() { pause(); state.reviewing = false; idle.reset(); controls(); },
    thumbnail(context, clip, rectangle) {
      if (!clip?.available) return;
      // Outfit cards share the stage scale: common-canvas padding must not make
      // one costume look smaller than another. This is never per-frame fitting.
      const factor = Math.min(rectangle[2], rectangle[3]) / 832, target = destinationRect(clip, catalog.master);
      const x = rectangle[0] + (rectangle[2] - 832 * factor) / 2;
      const y = rectangle[1] + (rectangle[3] - 832 * factor) / 2;
      context.save(); context.beginPath(); context.rect(...rectangle); context.clip();
      drawCell(context, clip, 0, [x + target[0] * factor, y + (target[1] - 160) * factor, target[2] * factor, target[3] * factor]); context.restore();
    } } });
async function loadClockArt() {
  if (!experienceUI) return;
  try {
    const url = new URL('experience/clock/manifest.json', repo); url.searchParams.set('v', revision);
    const result = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(10000) });
    if (!result.ok) throw new Error('手臂時計素材還未載入');
    const manifest = await result.json(), source = manifest.source;
    if (!source || !manifest.frameRegions || !manifest.canvas) throw new Error('手臂時計素材尚未齊全');
    const count = Math.max(manifest.body?.regionIndex ?? 0, ...(manifest.hands || []).map(hand => hand.regionIndex)) + 1;
    const clip = normalizeClip({ id: 'experience-clock-rig', title: '原味手臂時計', atlas: source.path, width: source.width, height: source.height,
      sha256: source.sha256, frameRegions: manifest.frameRegions, frameCount: count, durationsMs: Array(count).fill(1000) });
    await loadClip(clip);
    if (!clip.available) throw new Error(clip.loadError);
    if (clip.renderCanvas.width !== manifest.canvas.width || clip.renderCanvas.height !== manifest.canvas.height) throw new Error('手臂時計共同畫布不一致');
    experienceUI.setClockRig(createClockRig(manifest, frameCanvases.get(clip.id))); shell.report.clockArtLoaded = true;
  } catch (error) { shell.report.clockArtLoaded = false; shell.report.clockArtError = String(error.message || error); }
}
shell.ready();
if (shell.report.clipsFailed.length) {
  $('#recovery-message').textContent = `${shell.report.clipsFailed.length} 組畫稿未載入，其他動作可照常檢視。重試會保留意見。`;
  $('#preview-recovery').hidden = false;
}
const initial = sceneDefault() || clips.find(clip => clip.available);
selectClip(initial); $('#scene').value = state.scene; updateSceneText(); controls(); updateCompanion();
const requestedCandidateGroup = new URL(location.href).searchParams.get('group');
if (candidateMode && Object.hasOwn(candidateFilters, requestedCandidateGroup)) applyCandidateFilter(requestedCandidateGroup);
if (!candidateMode) loadClockArt();
if (!candidateMode) setInterval(() => {
  const next = idle.step(performance.now(), { eligible: automaticAllowed(context()), playing: state.playing, clips: idleClips() });
  if (next) playClip(next, 'idle');
  updateIdleStatus();
}, 200);
if (!candidateMode) setInterval(updateCompanion, 1000);
