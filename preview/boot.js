// Real digital clocks and retry controls remain independent of artwork/modules.
(() => {
  const build = '20261008-break1';
  const candidates = new URL(location.href).searchParams.get('review') === 'candidates';
  if (candidates) {
    document.body.dataset.review = 'candidates';
    document.querySelector('#candidate-banner').hidden = false;
    document.title = '派大星 · 待修動畫審稿';
  }
  const status = document.querySelector('#status');
  let clockPreferences = { timeFormat: '24', showDate: true };
  if (!candidates) {
    try { const saved = JSON.parse(localStorage.getItem('patrick.experience.v1'))?.settings; if (saved) clockPreferences = { timeFormat: saved.timeFormat === '12' ? '12' : '24', showDate: saved.showDate !== false }; } catch { /* Clock remains independent when storage is unavailable. */ }
  }
  const recovery = document.querySelector('#preview-recovery');
  const controls = [...document.querySelectorAll('[data-ready]')];
  const report = { build, status: 'loading', frames: 0, lastError: null };
  const lock = value => controls.forEach(control => { control.disabled = value; });
  function clock() {
    const date = new Date();
    const hour = clockPreferences.timeFormat === '12' ? date.getHours() % 12 || 12 : date.getHours();
    const period = clockPreferences.timeFormat === '12' ? date.getHours() < 12 ? 'AM' : 'PM' : '';
    const time = `${String(hour).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
    document.querySelectorAll('[data-clock]').forEach(digital => { digital.textContent = time; digital.dataset.period = period; digital.dateTime = date.toISOString(); digital.setAttribute('aria-label', `現在時間 ${time} ${period}`); });
    document.querySelectorAll('[data-watch-date]').forEach(label => { label.textContent = new Intl.DateTimeFormat('zh-Hant', { weekday: 'short', month: 'numeric', day: 'numeric' }).format(date); label.hidden = !clockPreferences.showDate; });
    report.timeFormat = clockPreferences.timeFormat;
  }
  function fail(error) {
    report.status = 'error'; report.lastError = String(error?.message || error);
    status.textContent = '畫稿沒有載入完成，請重試。';
    document.querySelector('#recovery-message').textContent = `${report.lastError}。時間仍會顯示，重試會保留審稿意見。`;
    recovery.hidden = false; lock(true);
  }
  const watchdog = setTimeout(() => { if (report.status === 'loading') fail(new Error('載入超時')); }, 30000);
  window.__patrickPreviewShell = { build, report, fail, setClockPreferences(value) { clockPreferences = { timeFormat: value.timeFormat === '12' ? '12' : '24', showDate: value.showDate !== false }; clock(); }, ready() {
    report.status = 'ready'; recovery.hidden = true; lock(false); clearTimeout(watchdog);
  }};
  document.querySelector('#retry-preview').addEventListener('click', () => {
    const url = new URL(location.href); url.searchParams.set('v', build); url.searchParams.set('retry', String(Date.now())); location.replace(url.href);
  });
  lock(true); clock(); setInterval(clock, 1000);
  import(`./app.js?v=${build}`).catch(fail);
})();
