import { STORAGE_KEY, GOODNIGHT_STEPS, createRun, receiveReceipt, retryFailed, summarize, restoreRun } from './routine-run-core.js?v=20261013-1';

const host = document.getElementById('routine-rehearsal');
const statusLabels = { pending: '等待回報', succeeded: '已完成', failed: '未成功', skipped: '按選擇略過' };
const node = (tag, text, className = '') => { const item = document.createElement(tag); item.textContent = text; item.className = className; return item; };
let run = null;
let storageWarning = '';
try {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved) { run = restoreRun(saved); if (!run) storageWarning = '上次試演記錄無法讀取。可以重新開始；其他設定不受影響。'; }
} catch { storageWarning = '此瀏覽器暫時無法保存試演；本次仍可操作。'; }

host.innerHTML = `<div class="rehearsal-intro"><span class="rehearsal-label">流程試演 · 不會操作裝置</span><h2 id="rehearsal-title">哪一步沒完成，就接著處理那一步。</h2><p>先試一次「晚安」遇到小意外的情況。完成的步驟保留，沒收到消息的步驟繼續等待；重新整理，也能接著查看。</p><small>下面使用示範結果，與 App 的實際執行記錄分開。沒有切換你的睡眠專注、設定鬧鐘或控制燈光。</small></div>
<div class="rehearsal-body"><div class="rehearsal-controls"><label for="rehearsal-preset">這次想試哪種情況？</label><select id="rehearsal-preset"><option value="mixed">手機前三步完成，燈光沒有成功</option><option value="skipped">只準備睡眠專注和派大星</option><option value="missing">睡眠專注沒有傳回結果</option></select><button id="rehearsal-start" type="button">開始一次試演</button><button id="rehearsal-clear" class="secondary" type="button">清除本頁試演</button><p>「只準備睡眠專注和派大星」會略過鬧鐘與燈光，保留你原有的設定。這是配方選擇，不算執行失敗。</p><p id="rehearsal-storage-note"></p></div>
<div class="rehearsal-results"><p id="rehearsal-summary" class="rehearsal-summary" role="status" aria-live="polite"></p><p id="rehearsal-watch" class="rehearsal-watch">手錶專注尚未確認。手機步驟有回報，也不能代表手錶已切換。</p><ol id="rehearsal-steps" class="rehearsal-steps"></ol><div id="rehearsal-retry" class="rehearsal-retry"><button id="rehearsal-retry-failed" type="button">只重試未成功的步驟</button><p class="rehearsal-meta">按下重試後，仍要等新的結果，才知道這次有沒有完成。</p><label for="rehearsal-reply">下一次示範回報</label><select id="rehearsal-reply"><option value="succeeded">這次完成了</option><option value="failed">這次仍未成功</option></select><div class="actions"><button id="rehearsal-reply-retry" class="secondary" type="button">補上重試結果</button><button id="rehearsal-reply-missing" class="secondary" type="button">補上等待中的回報</button></div></div><p id="rehearsal-notice" class="rehearsal-notice" role="status" aria-live="polite"></p><p id="rehearsal-meta" class="rehearsal-meta"></p><details id="rehearsal-history" class="rehearsal-history"><summary>看看這次收到的回報</summary><ol id="rehearsal-history-list"></ol></details></div></div>`;
const $ = id => document.getElementById(id);
function save() {
  try { if (run) localStorage.setItem(STORAGE_KEY, JSON.stringify(run)); else localStorage.removeItem(STORAGE_KEY); storageWarning = ''; }
  catch { storageWarning = '這次變化未能保存。重新整理後可能回到上次記錄。'; }
}
function clock(value) { return new Intl.DateTimeFormat('zh-Hant', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(new Date(value)); }
function render(message = '') {
  $('rehearsal-storage-note').textContent = storageWarning || '試演只存在這個瀏覽器。清除時不會刪除素材意見、角色設定或 App 記錄。';
  $('rehearsal-notice').textContent = message;
  const list = $('rehearsal-steps'); list.replaceChildren();
  $('rehearsal-retry').hidden = !run; $('rehearsal-history').hidden = !run;
  $('rehearsal-clear').disabled = !run && !storageWarning;
  $('rehearsal-summary').dataset.outcome = run ? summarize(run).outcome : 'empty';
  if (!run) {
    $('rehearsal-summary').textContent = '選一個情況，試著說聲晚安。';
    $('rehearsal-meta').textContent = '';
    list.append(node('li', '手機和派大星的四個步驟，會分開顯示結果。', 'rehearsal-empty'));
    document.documentElement.dataset.routineRehearsal = 'ready'; return;
  }
  const result = summarize(run);
  $('rehearsal-summary').textContent = result.failed ? `試演：${result.failed} 步未成功${result.pending ? `，${result.pending} 步還在等回報` : '，其餘結果已保留'}。`
    : result.pending ? `試演：${result.pending} 步還在等回報，不能算全部完成。`
    : result.skipped ? `試演：選定的手機步驟已回報完成，${result.skipped} 個選配已略過。`
    : '試演：四個手機步驟都已回報完成。';
  for (const [index, step] of run.steps.entries()) {
    const item = node('li', ''); item.dataset.stepId = step.stepID; item.dataset.state = step.status; item.dataset.attempt = step.attempt;
    item.append(node('span', String(index + 1).padStart(2, '0'), 'step-number'));
    const definition = GOODNIGHT_STEPS.find(item => item.stepID === step.stepID);
    const body = node('div', ''), top = node('div', '', 'rehearsal-step-top'), title = node('h3', definition.title);
    if (!definition.required) title.append(node('span', '選配', 'rehearsal-option'));
    top.append(title, node('span', statusLabels[step.status], 'rehearsal-state')); body.append(top);
    const note = step.status === 'pending' ? (step.attempt > 1 ? `第 ${step.attempt} 次嘗試已準備，等待新的示範回報。` : '沒有收到結果，暫時不判斷成功或失敗。') : step.note;
    if (note) body.append(node('p', note));
    item.append(body); list.append(item);
  }
  $('rehearsal-retry-failed').disabled = !run.steps.some(step => step.status === 'failed' && step.attempt < 5);
  $('rehearsal-reply-retry').disabled = !run.steps.some(step => step.status === 'pending' && step.attempt > 1);
  $('rehearsal-reply-missing').disabled = !run.steps.some(step => step.status === 'pending' && step.attempt === 1);
  $('rehearsal-meta').textContent = `這次試演開始於 ${clock(run.createdAtMS)}。重新整理會保留目前進度。`;
  const history = $('rehearsal-history-list'); history.replaceChildren();
  for (const receipt of [...run.events].reverse()) {
    const title = GOODNIGHT_STEPS.find(step => step.stepID === receipt.stepID).title;
    history.append(node('li', `${clock(receipt.receivedAtMS)} · ${title} · 第 ${receipt.attempt} 次：${statusLabels[receipt.status]}。${receipt.note || ''}`));
  }
  if (!run.events.length) history.append(node('li', '尚未收到示範回報。'));
  if (run.steps.some(step => step.status === 'failed' && step.attempt === 5)) $('rehearsal-notice').textContent += ' 同一步已試了五次。先檢查原因，或開始新的一次試演。';
  document.documentElement.dataset.routineRehearsal = 'ready';
}
function deliver(stepID, status, note) {
  const now = Date.now(), step = run.steps.find(item => item.stepID === stepID);
  const receipt = { receiptID: crypto.randomUUID(), executionID: run.executionID, stepID, attempt: step.attempt, status, source: stepID === 'patrick-state' ? 'localApp' : 'shortcut', note, receivedAtMS: now };
  const result = receiveReceipt(run, receipt, now);
  if (result.accepted) run = result.run;
}
$('rehearsal-start').addEventListener('click', () => {
  run = createRun({ executionID: crypto.randomUUID(), now: Date.now() });
  const preset = $('rehearsal-preset').value;
  if (preset !== 'missing') deliver('sleep-focus', 'succeeded', '示範：手機睡眠專注步驟回報完成。');
  deliver('existing-alarm', preset === 'skipped' ? 'skipped' : 'succeeded', preset === 'skipped' ? '這次沒有選擇調整鬧鐘。' : '示範：選好的既有鬧鐘已回報啟用；沒有新增鬧鐘。');
  deliver('patrick-state', 'succeeded', '示範：手機上的派大星已回報準備晚安；手錶狀態另行確認。');
  deliver('home-scene', preset === 'mixed' ? 'failed' : 'skipped', preset === 'mixed' ? '示範：燈光場景這次回報未成功。' : '這次沒有選擇執行燈光場景。');
  save(); render('新的一次試演已開始。');
});
$('rehearsal-retry-failed').addEventListener('click', () => {
  const result = retryFailed(run, Date.now()); run = result.run; save();
  render(`只準備重試 ${result.retriedStepIDs.length} 個未成功步驟；已完成和略過的步驟保持原樣。`);
});
function replyToPending(retry) {
  if (!run) return;
  const selected = run.steps.filter(step => step.status === 'pending' && (retry ? step.attempt > 1 : step.attempt === 1));
  const status = $('rehearsal-reply').value;
  for (const step of selected) deliver(step.stepID, status, status === 'succeeded' ? '示範：這次已收到完成回報。' : '示範：這次回報仍未成功，可以再試。');
  save(); render(`已補上 ${selected.length} 個示範回報。`);
}
$('rehearsal-reply-retry').addEventListener('click', () => replyToPending(true));
$('rehearsal-reply-missing').addEventListener('click', () => replyToPending(false));
$('rehearsal-clear').addEventListener('click', () => { run = null; storageWarning = ''; save(); render('已清除本頁試演。其他資料保持原樣。'); });
render(run ? '已接回上次試演。' : '');
