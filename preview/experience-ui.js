import { EXPERIENCE_KEY, TIMER_KINDS, isExerciseKind, restoreExperience, careNow, careAction, appendJournal, timerRemaining,
  startActivity, controlActivity, finishActivity, claimEgg, isSleepMinute } from './experience-core.js?v=20261006-size2';
import { holidayFor } from './pet-core.js?v=20261006-size2';
import { DEFAULT_LAYOUT, validateLayouts } from './layout-core.js?v=20261006-size2';

const $ = selector => document.querySelector(selector);
export async function createExperience({ repo, revision, clips, read, write, getPet, setPet, player, shell }) {
  const savedExperience = read(EXPERIENCE_KEY);
  let experience = restoreExperience(savedExperience), unlocked = false, audio = null, speechTimer = null;
  const legacyPet = read('patrick.pet.v1');
  if (legacyPet?.version === 1) for (const [key, field] of [['sleepStartMinutes', 'sleepStart'], ['sleepEndMinutes', 'sleepEnd']]) {
    if (!Number.isFinite(savedExperience?.settings?.[key]) && Number.isFinite(legacyPet[field])) experience.settings[key] = Math.max(0, Math.min(23, Math.floor(legacyPet[field]))) * 60;
  }
  if (!savedExperience && getPet().activity) {
    const legacy = getPet().activity, kind = legacy.mode === 'breathing' ? 'breathing' : legacy.mode === 'focus' ? 'focus' : 'exercise';
    experience = startActivity(experience, kind, (legacy.endsAt - legacy.startedAt) / 1000, legacy.startedAt);
    write(EXPERIENCE_KEY, experience);
  }
  let effectsStarted = performance.now(), effectUntil = 0, transientEffect = null, visualRAF = null, taps = [];
  let clockRig = null;
  let lastAutomaticScene = null;
  let actionOutfitId = null, actionOutfitUntil = 0;
  async function json(path) {
    try { const url = new URL(path, repo); url.searchParams.set('v', revision); const response = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(10000) }); return response.ok ? await response.json() : null; } catch { return null; }
  }
  const [themes, sounds, layoutManifest] = await Promise.all([json('experience/themes.json'), json('experience/audio/manifest.json'), json('experience/layouts.json')]);
  let layouts = [DEFAULT_LAYOUT];
  try { layouts = validateLayouts(layoutManifest); } catch { $('#layout-description').textContent = '版式資料未載入，先使用經典版。'; }
  const layout = () => layouts.find(value => value.id === experience.settings.layoutID) || layouts[0];
  for (const value of layouts) {
    const option = document.createElement('option'); option.value = value.id; option.textContent = value.title; $('#face-layout').append(option);
  }
  $('#layout-picker').hidden = false;
  $('#face-layout').addEventListener('change', event => {
    experience.settings.layoutID = event.target.value; save(); updatePreferences();
  });
  const available = id => clips.find(clip => clip.id === id && clip.available);
  const outfits = (Array.isArray(themes?.outfits) ? themes.outfits : []).filter(outfit => typeof outfit.id === 'string' && available(outfit.clipId));
  if (!outfits.length) {
    const first = clips.find(clip => clip.available);
    outfits.push({ id: 'classic', title: '經典睡衣', scene: 'sleeping', clipId: first.id, actions: {}, ambience: 'none' });
  }
  if (experience.outfitId !== 'auto' && !outfits.some(outfit => outfit.id === experience.outfitId)) experience.outfitId = 'auto';
  const overlays = [$('#ambience-large'), $('#ambience-small')];
  const overlayContexts = overlays.map(canvas => canvas.getContext('2d'));
  const titleForScene = { auto: '跟著時間', awake: '日常', sleeping: '睡前', charging: '充電', exercise: '運動', focus: '專心', bath: '洗澡', celebrate: '節日' };
  function resolvedScene() {
    if (player.state.scene !== 'auto') return player.state.scene;
    const activity = experience.activity;
    if (activity && !activity.completedAt) return isExerciseKind(activity.kind) ? 'exercise' : 'focus';
    const date = new Date(), minute = date.getHours() * 60 + date.getMinutes();
    return isSleepMinute(minute, experience.settings.sleepStartMinutes, experience.settings.sleepEndMinutes) ? 'sleeping' : 'awake';
  }
  function outfit() { return outfits.find(item => item.id === experience.outfitId)
    || outfits.find(item => item.id === actionOutfitId)
    || outfits.find(item => item.id === themes?.defaultSceneOutfits?.[resolvedScene()])
    || outfits.find(item => item.scene === resolvedScene()) || outfits[0]; }
  function actionClips(action) {
    const value = outfit().actions?.[action]; return (Array.isArray(value) ? value : value ? [value] : []).map(available).filter(Boolean);
  }
  function actionClip(action) { return actionClips(action)[0] || null; }
  function save() {
    const ok = write(EXPERIENCE_KEY, experience);
    $('#experience-save-status').textContent = ok ? '' : '這個瀏覽器暫時不能保存；可先把日記下載留存。'; return ok;
  }
  function journal(type, text) { experience = appendJournal(experience, type, text); save(); }
  function say(text, duration = 3000) {
    $('#companion-line').textContent = text; $('#watch-speech').textContent = text;
    $('#watch-speech').hidden = false; clearTimeout(speechTimer);
    speechTimer = setTimeout(() => { $('#watch-speech').hidden = true; }, duration);
  }
  function gesture(event) { if (event?.isTrusted) unlocked = true; }
  function soundPath(kind) {
    const collection = sounds?.sounds || sounds?.files || sounds?.cues;
    const value = Array.isArray(collection) ? collection.find(item => item.id === kind || item.name === kind) : collection?.[kind];
    return typeof value === 'string' ? value : value?.path || value?.file || null;
  }
  function feedback(kind, event, forceSound = false) {
    gesture(event);
    if (!unlocked || player.quiet()) return;
    if (experience.settings.haptics && typeof navigator.vibrate === 'function') navigator.vibrate(18);
    if (!experience.settings.sound && !forceSound) return;
    const path = soundPath(kind) || soundPath('softclick') || soundPath('pet');
    if (!path) { $('#sound-status').textContent = '聲音素材尚未載入，互動和計時照常。'; return; }
    const url = new URL(path, repo);
    if (url.origin !== repo.origin || !url.pathname.startsWith(repo.pathname)) return;
    audio?.pause(); audio = new Audio(url.href); audio.volume = 0.32;
    audio.play().then(() => { $('#sound-status').textContent = '已開啟互動聲音；安靜或背景時不播放。'; })
      .catch(() => { $('#sound-status').textContent = '這次沒有播出聲音；可再按「試聽一聲」。'; });
  }
  function playAction(action) {
    if (experience.outfitId === 'auto') {
      const preferred = outfits.find(item => item.id === themes?.defaultActionOutfits?.[action]);
      if (preferred) actionOutfitId = preferred.id;
    }
    const clip = actionClip(action); if (!clip) return false;
    actionOutfitUntil = Date.now() + clip.totalMs + 3500; refreshOutfitSelection();
    return player.play(clip, 'interaction');
  }
  function burst(kind, seconds = 2.5) {
    if (player.quiet() || !experience.settings.bubbles) return;
    transientEffect = kind; effectUntil = performance.now() + seconds * 1000; startVisuals();
  }
  function petAction(event) {
    gesture(event); setPet({ type: 'tap' }); experience = careAction(experience, 'pet');
    journal('pet', '摸摸頭，熟悉了一點。'); feedback('pet', event); playAction('pet');
    const now = Date.now(); taps = [...taps.filter(at => now - at < 1400), now];
    if (taps.length >= 3) { taps = []; surprise(event, 'three-taps'); }
    else say(['嗯？有在聽。', '好啦，靠近一點。', '只是剛好讓你摸一下。'][getPet().taps % 3]);
    refresh();
  }
  function feedAction(event) {
    gesture(event); setPet({ type: 'feed' });
    if (getPet().lastEvent?.type === 'full') { say('剛吃一口，等三秒再餵啦。'); return; }
    experience = careAction(experience, 'feed'); journal('feed', '吃到一口小點心。');
    feedback('feed', event); const performed = playAction('feed'); burst('stars', 1.6);
    say(performed && experience.outfitId === 'auto' ? `${outfit().title}上場，這一口記住了。` : '這一口，記住了。再陪我坐一下。'); refresh();
  }
  function surprise(event, id = 'little-surprise') {
    gesture(event); const claimed = claimEgg(experience, id, 45000);
    if (!claimed.claimed) { say('剛剛才演過，讓我歇一下。'); return; }
    experience = claimed.state; journal('surprise', id === 'three-taps' ? '連摸三下，發現他其實沒睡。' : '碰上了一個小驚喜。');
    playAction('surprise') || playAction('pet'); burst('confetti'); feedback('surprise', event);
    say(id === 'three-taps' ? '我沒睡，我只是閉眼想事情。' : '今日特別任務：偷閒三秒。'); refresh();
  }
  function calendarMoment(holiday, manual = false) {
    if (!holiday || (manual && player.quiet()) || (!player.quiet() && !manual && (player.state.reviewing || player.state.playing))) return;
    const localDate = new Date(), day = `${localDate.getFullYear()}-${String(localDate.getMonth() + 1).padStart(2, '0')}-${String(localDate.getDate()).padStart(2, '0')}`;
    const id = manual ? 'calendar-preview' : holiday.id === 'birthday' ? `birthday-${day}` : `calendar-${day}-${holiday.id}`;
    const claimed = claimEgg(experience, id, manual ? 30000 : 24 * 3600000);
    if (!claimed.claimed) return;
    experience = claimed.state;
    if (player.quiet()) { save(); return; }
    journal('celebrate', manual ? `看了一段${holiday.name}小劇場。` : `今天是${holiday.name}，留一份小小祝福。`);
    playAction('celebrate'); burst('confetti', 3); say(`${holiday.name}快樂！今天這三秒，特別留給你。`, 4500); feedback('complete');
  }
  function switchTab(name) {
    document.querySelectorAll('[data-experience-tab]').forEach(button => button.setAttribute('aria-selected', String(button.dataset.experienceTab === name)));
    document.querySelectorAll('[data-experience-panel]').forEach(panel => { panel.hidden = panel.dataset.experiencePanel !== name; });
  }
  function chooseOutfit(id, event) {
    if (id !== 'auto' && !outfits.some(item => item.id === id)) return;
    gesture(event); experience.outfitId = id; actionOutfitId = null; save(); player.resume();
    const selected = outfit(); player.select(available(selected.clipId)); journal('outfit', `換上${id === 'auto' ? '跟隨情境的造型' : selected.title}。`);
    say(id === 'auto' ? '衣服跟著今天慢慢換。' : `今天就穿${selected.title}。`); feedback('change', event); refresh(); startVisuals();
  }
  function refreshOutfitSelection() {
    document.querySelectorAll('[data-outfit]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.outfit === experience.outfitId)));
    const selected = outfit(), actions = [selected.actions?.pet ? '摸摸頭' : '', selected.actions?.feed ? '吃點心' : '', selected.actions?.yawn ? '睡前哈欠' : '', selected.actions?.idle ? '偶爾眨眼' : ''].filter(Boolean);
    $('#outfit-description').textContent = `${selected.title} · ${titleForScene[selected.scene] || '日常'}${actions.length ? ` · ${actions.join('、')}` : ''}`;
    shell.report.outfit = selected.id; shell.report.outfitPreference = experience.outfitId;
  }
  for (const item of [{ id: 'auto', title: '跟著情境', clipId: outfits[0].clipId }, ...outfits]) {
    const button = document.createElement('button'); button.type = 'button'; button.dataset.outfit = item.id;
    const canvas = document.createElement('canvas'); canvas.width = 120; canvas.height = 120; canvas.setAttribute('aria-hidden', 'true');
    player.thumbnail(canvas.getContext('2d'), available(item.clipId), [0, 0, 120, 120]);
    const title = document.createElement('span'); title.textContent = item.title; button.append(canvas, title);
    button.addEventListener('click', event => chooseOutfit(item.id, event)); $('#outfit-grid').append(button);
  }
  function startTimer(kind, seconds, event) {
    gesture(event); experience = startActivity(experience, kind, seconds); journal('timer', `開始${TIMER_KINDS[kind]}陪伴。`);
    player.changeScene(isExerciseKind(kind) ? 'exercise' : 'focus');
    $('#activity-kind').value = kind; $('#activity-minutes').value = String(seconds / 60);
    switchTab('timer'); say(kind === 'breathing' ? '照自己的步調，慢慢來。' : '開始了，我在旁邊。'); feedback('start', event); refresh();
  }
  function updateTimer() {
    const now = Date.now(), previous = experience.activity;
    const finished = finishActivity(experience, now);
    if (finished !== experience) {
      experience = finished; save();
      if (!player.quiet() && previous.endsAt > player.noCatchupBefore() && !player.state.reviewing) {
        feedback('complete'); playAction('celebrate'); burst('stars'); say('這一段完成啦。休息一下也很好。', 4500);
      }
      renderJournal();
    }
    const activity = experience.activity, remaining = Math.ceil(timerRemaining(activity, now) / 1000);
    $('#timer-status').textContent = !activity ? '準備好就開始。' : activity.completedAt !== null ? `${TIMER_KINDS[activity.kind]}完成了。`
      : `${activity.paused ? '已暫停 · ' : ''}${TIMER_KINDS[activity.kind]} ${String(Math.floor(remaining / 60)).padStart(2, '0')}:${String(remaining % 60).padStart(2, '0')}`;
    $('#activity-progress').value = activity ? 1 - timerRemaining(activity, now) / activity.durationMs : 0;
    $('#pause-activity').disabled = !activity || activity.paused || activity.completedAt !== null;
    $('#resume-activity').hidden = !activity?.paused; $('#stop-timer').disabled = !activity;
    const breathing = activity?.kind === 'breathing' && activity.completedAt === null;
    $('#breath-guide').hidden = !breathing;
    if (breathing) {
      const elapsed = activity.durationMs - timerRemaining(activity, now), phase = elapsed % 10000;
      $('#breath-phase').textContent = activity.paused || player.quiet() ? '先安靜停一下' : phase < 4000 ? '慢慢吸氣' : '慢慢吐氣';
      $('#breath-guide').style.setProperty('--breath-scale', activity.paused || player.quiet() ? '1' : String(phase < 4000 ? 1 + phase / 4000 * .18 : 1.18 - (phase - 4000) / 6000 * .18));
    }
    shell.report.activity = activity ? { id: activity.id, kind: activity.kind, paused: activity.paused, remainingMs: timerRemaining(activity, now), completedAt: activity.completedAt } : null;
    updateLayoutInfo(now);
  }
  function updateLayoutInfo(now = Date.now()) {
    const activity = experience.activity, seconds = Math.ceil(timerRemaining(activity, now) / 1000), care = careNow(experience.care, now);
    for (const panel of document.querySelectorAll('.layout-information')) {
      panel.querySelector('[data-layout-title]').textContent = activity ? TIMER_KINDS[activity.kind].replace('陪伴', '') : '陪伴倒數';
      panel.querySelector('[data-layout-countdown]').textContent = activity ? `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}` : '—:—';
      panel.querySelector('[data-layout-state]').textContent = !activity ? '還沒開始' : activity.completedAt !== null ? '這段完成了' : activity.paused ? '已暫停' : '一起慢慢來';
      panel.querySelector('[data-layout-progress]').value = activity ? 1 - timerRemaining(activity, now) / activity.durationMs : 0;
      panel.querySelector('[data-layout-care]').textContent = `飽足 ${Math.round(care.satiety)}%`;
    }
  }
  function renderJournal() {
    const list = $('#local-journal'); list.replaceChildren();
    if (!experience.journal.length) { const empty = document.createElement('li'); empty.textContent = '還沒有紀錄。一起做點小事，就會留在這裡。'; list.append(empty); return; }
    for (const entry of [...experience.journal].reverse()) {
      const item = document.createElement('li'), time = document.createElement('time'), text = document.createElement('span');
      time.dateTime = new Date(entry.at).toISOString(); time.textContent = new Intl.DateTimeFormat('zh-Hant', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(entry.at);
      text.textContent = entry.text; item.append(time, text); list.append(item);
    }
  }
  function refresh() {
    const care = careNow(experience.care), pet = getPet();
    $('#care-satiety').textContent = `${Math.round(care.satiety)}%`; $('#care-bond').textContent = Math.round(care.bond);
    $('#satiety-meter').value = care.satiety; $('#bond-meter').value = care.bond;
    $('#care-counts').textContent = `一起吃了 ${pet.fed} 口 · 摸摸頭 ${pet.taps} 次`;
    refreshOutfitSelection(); renderJournal(); updateTimer();
    shell.report.care = { satiety: care.satiety, bond: care.bond, totalFeeds: pet.fed, totalPets: pet.taps };
  }
  function sceneChanged(entry) {
    if (entry) journal('scene', `切到${titleForScene[player.state.scene] || '日常'}情境。`);
    refreshOutfitSelection(); startVisuals();
  }
  function drawVisuals(time) {
    visualRAF = null;
    overlayContexts.forEach(context => context?.clearRect(0, 0, 832, 992));
    const quiet = player.quiet();
    const arms = clockRig && experience.settings.clockMode === 'arms' && !player.state.playing;
    if (arms && !document.hidden) shell.report.armAngles = clockRig.draw(overlayContexts, new Date(), layout().characterTransform);
    shell.report.armClockActive = Boolean(arms && !document.hidden);
    if (quiet) { audio?.pause(); shell.report.ambienceActive = false; shell.report.clockMode = experience.settings.clockMode; return; }
    const scene = resolvedScene(), ambience = time < effectUntil ? transientEffect : ['charging', 'bath'].includes(scene) ? 'bubbles' : outfit().ambience;
    const active = experience.settings.bubbles && ['bubbles', 'stars', 'snow', 'confetti'].includes(ambience);
    if (active) {
      const seconds = (time - effectsStarted) / 1000;
      for (const context of overlayContexts) {
        context.save(); context.beginPath(); context.rect(0, 260, 832, 650); context.clip();
        for (let i = 0; i < 13; i++) {
          const x = 55 + ((i * 131 + Math.sin(seconds * .45 + i) * 16) % 725 + 725) % 725;
          const y = 950 - ((seconds * (18 + i % 4 * 7) + i * 79) % 710);
          context.globalAlpha = .12 + (i % 3) * .035; context.strokeStyle = i % 2 ? '#c8f8ff' : '#f5d7ff'; context.fillStyle = ['#fbd9ed', '#d7f6e8', '#fff0bd'][i % 3];
          if (ambience === 'bubbles') { context.lineWidth = 2; context.beginPath(); context.arc(x, y, 8 + i % 4 * 5, 0, Math.PI * 2); context.stroke(); }
          else if (ambience === 'snow') { context.beginPath(); context.arc(x, y, 2 + i % 3, 0, Math.PI * 2); context.fill(); }
          else { context.save(); context.translate(x, y); context.rotate(seconds * .25 + i); context.fillRect(-3, -7, 6, ambience === 'stars' ? 14 : 9); if (ambience === 'stars') context.fillRect(-7, -3, 14, 6); context.restore(); }
        }
        context.restore();
      }
    }
    shell.report.ambienceActive = active; shell.report.clockMode = experience.settings.clockMode;
    if (active || (clockRig && experience.settings.clockMode === 'arms')) visualRAF = requestAnimationFrame(drawVisuals);
  }
  function startVisuals() {
    cancelAnimationFrame(visualRAF); visualRAF = null; effectsStarted = performance.now();
    if (player.quiet()) { drawVisuals(performance.now()); audio?.pause(); shell.report.ambienceActive = false; return; }
    drawVisuals(performance.now());
  }
  function heartbeat() {
    updateTimer(); const care = careNow(experience.care); $('#care-satiety').textContent = `${Math.round(care.satiety)}%`; $('#satiety-meter').value = care.satiety;
    if (player.quiet() && !document.hidden && clockRig && experience.settings.clockMode === 'arms') drawVisuals(performance.now());
    if (actionOutfitId && Date.now() >= actionOutfitUntil && !document.hidden && !player.state.playing && !player.state.reviewing) {
      actionOutfitId = null; player.select(available(outfit().clipId)); refreshOutfitSelection();
    }
    const automaticScene = resolvedScene();
    if (player.state.scene === 'auto' && experience.outfitId === 'auto' && lastAutomaticScene !== automaticScene && !player.state.playing && !player.state.reviewing) {
      lastAutomaticScene = automaticScene; player.select(available(outfit().clipId)); refreshOutfitSelection(); startVisuals();
    }
    const date = new Date(), holiday = holidayFor(date, getPet().birthday);
    if (holiday && (holiday.id === 'birthday' || experience.settings.holidaysEnabled)) calendarMoment(holiday);
    if (player.quiet() || player.state.reviewing || player.state.playing) return;
    if (date.getMinutes() === 0 && date.getSeconds() < 2 && Date.now() - player.noCatchupBefore() > 3000) {
      const claimed = claimEgg(experience, 'hourly', 3600000);
      if (claimed.claimed) { experience = claimed.state; save(); playAction('celebrate'); burst('stars', 1.6); say('又過一小時啦，伸伸懶腰。'); }
    }
  }
  function updatePreferences() {
    $('#face-layout').value = layout().id; $('#layout-description').textContent = layout().description;
    player.setLayout(layout()); updateLayoutInfo();
    shell.setClockPreferences?.({ timeFormat: experience.settings.timeFormat, showDate: experience.settings.showDate });
    $('#sound-enabled').checked = experience.settings.sound; $('#haptics-enabled').checked = experience.settings.haptics;
    $('#ambience-enabled').checked = experience.settings.bubbles; $('#date-enabled').checked = experience.settings.showDate;
    $('#holidays-enabled').checked = experience.settings.holidaysEnabled;
    const timeText = value => `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`;
    $('#sleep-start').value = timeText(experience.settings.sleepStartMinutes); $('#sleep-end').value = timeText(experience.settings.sleepEndMinutes);
    $('#time-format').value = experience.settings.timeFormat; $('#clock-mode').value = experience.settings.clockMode;
    $('#clock-mode-status').textContent = experience.settings.clockMode === 'arms' ? !clockRig ? '手臂造型還未載入，先保留數字與目前衣服。'
      : '原味手臂時計使用經典造型；接合位置仍在修稿。互動演完回到現在時間。數字模式會保留你選的衣服。' : '';
    startVisuals();
  }
  for (const button of document.querySelectorAll('[data-experience-tab]')) button.addEventListener('click', () => switchTab(button.dataset.experienceTab));
  for (const [id, key] of [['sound-enabled', 'sound'], ['haptics-enabled', 'haptics'], ['ambience-enabled', 'bubbles'], ['date-enabled', 'showDate'], ['holidays-enabled', 'holidaysEnabled']]) {
    $(`#${id}`).addEventListener('change', event => { gesture(event); experience.settings[key] = event.target.checked; if (key === 'sound' && !event.target.checked) audio?.pause(); save(); updatePreferences(); });
  }
  for (const [id, key] of [['time-format', 'timeFormat'], ['clock-mode', 'clockMode']]) $(`#${id}`).addEventListener('change', event => { gesture(event); experience.settings[key] = event.target.value; save(); updatePreferences(); });
  for (const [id, key] of [['sleep-start', 'sleepStartMinutes'], ['sleep-end', 'sleepEndMinutes']]) $(`#${id}`).addEventListener('change', event => {
    if (!/^\d{2}:\d{2}$/.test(event.target.value)) return;
    const [hour, minute] = event.target.value.split(':').map(Number);
    experience.settings[key] = hour * 60 + minute; actionOutfitId = null; lastAutomaticScene = null; save(); heartbeat(); sceneChanged(false);
  });
  $('#test-sound').addEventListener('click', event => feedback('tap', event, true));
  $('#little-surprise').addEventListener('click', event => surprise(event));
  $('#start-activity').addEventListener('click', event => startTimer($('#activity-kind').value, Number($('#activity-minutes').value) * 60, event));
  $('#exercise-timer').addEventListener('click', event => startTimer('exercise', 300, event));
  $('#breath-timer').addEventListener('click', event => startTimer('breathing', 60, event));
  function controlTimer(action) {
    const result = controlActivity(experience, action);
    experience = result.state; save(); refresh();
    if (result.status === 'completed') say('這一段已經完成了。');
    return result;
  }
  $('#pause-activity').addEventListener('click', () => controlTimer('pause'));
  $('#resume-activity').addEventListener('click', event => { gesture(event); controlTimer('resume'); });
  $('#birthday').value = getPet().birthday;
  $('#birthday').addEventListener('change', event => { setPet({ type: 'birthday', value: event.target.value }); $('#birthday').value = getPet().birthday; journal('birthday', getPet().birthday ? `記住生日 ${getPet().birthday}。` : '已清除生日。'); refresh(); });
  $('#export-journal').addEventListener('click', () => {
    const blob = new Blob([JSON.stringify({ schemaVersion: 1, exportedAt: new Date().toISOString(), journal: experience.journal, care: careNow(experience.care), activity: experience.activity }, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob), link = document.createElement('a'); link.href = url; link.download = 'patrick-little-days.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
  $('#toggle-review').addEventListener('click', () => { $('.editing').hidden = !$('.editing').hidden; if (!$('.editing').hidden) { player.hold(); $('.editing').scrollIntoView({ behavior: 'smooth', block: 'start' }); } });
  $('#experience-panel').hidden = false; $('.editing').hidden = true; document.body.dataset.experience = 'active';
  $('#show-guides').checked = false; $('.viewports').classList.add('guides-off');
  $('#catalog-summary').textContent = `${outfits.length} 套可穿造型 · 摸摸頭、餵一口，或陪你做完一件小事。`;
  $('#play').textContent = '演一下 ↗'; $('#birthday').value = getPet().birthday;
  updatePreferences(); refresh();
  return { experienceKey: EXPERIENCE_KEY, defaultClip: () => available(outfit().clipId), actionClip, idleClips: () => actionClips('idle'), resolvedScene,
    petAction, feedAction, refresh, sceneChanged, prepareScene() { actionOutfitId = null; }, quietChanged: startVisuals, frameChanged() { if (!visualRAF) drawVisuals(performance.now()); },
    focusTimer: event => startTimer('focus', 1500, event),
    cancelTimer() { controlTimer('cancel'); },
    moodChanged(value) { setPet({ type: 'mood', value }); journal('mood', `今天的心情：${$('#mood').selectedOptions[0].textContent}。`); say(value === 'tired' || value === 'low' ? '今天慢一點也沒關係。' : '好，我記住了。'); refresh(); },
    heartbeat, calendarMoment,
    setClockRig(rig) { clockRig = rig; updatePreferences(); },
    getSettings: () => ({ ...experience.settings }) };
}
