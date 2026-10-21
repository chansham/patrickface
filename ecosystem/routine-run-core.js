// Receipt model shared in shape with the native routine ledger.
// This browser module records demonstrations only and never executes a device action.
export const SCHEMA_VERSION = 1;
export const STORAGE_KEY = 'patrick.routine-rehearsal.v1';
export const GOODNIGHT_STEPS = Object.freeze([
  Object.freeze({ stepID: 'sleep-focus', title: '手機開啟睡眠專注', required: true }),
  Object.freeze({ stepID: 'existing-alarm', title: '啟用我選好的鬧鐘', required: false }),
  Object.freeze({ stepID: 'patrick-state', title: '派大星準備晚安', required: true }),
  Object.freeze({ stepID: 'home-scene', title: '執行我選好的燈光場景', required: false }),
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STATUSES = ['pending', 'succeeded', 'failed', 'skipped'];
const RECEIPT_STATUSES = ['succeeded', 'failed', 'skipped'];
const MAX_RECEIPTS = 20;
const timestamp = value => Number.isFinite(value) && value > 0;
const identifier = value => typeof value === 'string' && UUID.test(value);
const noteValid = value => typeof value === 'string' && value.length <= 240;
const copy = value => structuredClone(value);

export function createRun({ executionID, now }) {
  if (!identifier(executionID) || !timestamp(now)) throw new Error('Invalid execution identifier or time');
  return { schemaVersion: SCHEMA_VERSION, executionID, routineID: 'goodnight', createdAtMS: now, updatedAtMS: now,
    steps: GOODNIGHT_STEPS.map(step => ({ stepID: step.stepID, status: 'pending', attempt: 1, receiptID: null, source: null, note: null, updatedAtMS: now })), events: [] };
}

export function validateRun(run) {
  if (!run || run.schemaVersion !== SCHEMA_VERSION || !identifier(run.executionID) || run.routineID !== 'goodnight'
    || !timestamp(run.createdAtMS) || !timestamp(run.updatedAtMS) || run.updatedAtMS < run.createdAtMS
    || !Array.isArray(run.steps) || run.steps.length !== GOODNIGHT_STEPS.length
    || !Array.isArray(run.events) || run.events.length > MAX_RECEIPTS) return false;
  const ids = new Set();
  for (const receipt of run.events) {
    if (!receiptValid(receipt) || receipt.executionID !== run.executionID || receipt.receivedAtMS < run.createdAtMS
      || receipt.receivedAtMS > run.updatedAtMS || ids.has(receipt.receiptID)
      || !GOODNIGHT_STEPS.some(step => step.stepID === receipt.stepID && (receipt.status !== 'skipped' || !step.required))
      || ((receipt.stepID === 'patrick-state') !== (receipt.source === 'localApp'))) return false;
    ids.add(receipt.receiptID);
  }
  if (new Set(run.steps.map(step => step.stepID)).size !== GOODNIGHT_STEPS.length
    || run.updatedAtMS !== Math.max(...run.steps.map(step => step.updatedAtMS))) return false;
  return run.steps.every(step => {
    const definition = GOODNIGHT_STEPS.find(item => item.stepID === step.stepID);
    if (!definition || !STATUSES.includes(step.status) || !Number.isSafeInteger(step.attempt) || step.attempt < 1 || step.attempt > 5
      || !timestamp(step.updatedAtMS) || step.updatedAtMS < run.createdAtMS || step.updatedAtMS > run.updatedAtMS
      || (step.status === 'skipped' && definition.required)) return false;
    const history = run.events.filter(receipt => receipt.stepID === step.stepID);
    if (history.some(receipt => receipt.attempt > step.attempt || receipt.receivedAtMS > step.updatedAtMS)
      || new Set(history.map(receipt => receipt.attempt)).size !== history.length) return false;
    const ordered = [...history].sort((left, right) => left.attempt - right.attempt);
    if (ordered.some((receipt, index) => index > 0 && receipt.receivedAtMS < ordered[index - 1].receivedAtMS)) return false;
    for (let attempt = 1; attempt < step.attempt; attempt++) {
      if (!history.some(receipt => receipt.attempt === attempt && receipt.status === 'failed')) return false;
    }
    if (step.status === 'pending') return (step.attempt !== 1 || step.updatedAtMS === run.createdAtMS)
      && step.receiptID == null && step.source == null && step.note == null
      && !history.some(receipt => receipt.attempt === step.attempt);
    return noteValid(step.note) && identifier(step.receiptID) && run.events.some(receipt => receipt.receiptID === step.receiptID
      && receipt.stepID === step.stepID && receipt.attempt === step.attempt && receipt.status === step.status
      && receipt.source === step.source && receipt.note === step.note && receipt.receivedAtMS === step.updatedAtMS);
  });
}

function receiptValid(receipt) {
  return receipt && identifier(receipt.receiptID) && identifier(receipt.executionID) && typeof receipt.stepID === 'string'
    && Number.isSafeInteger(receipt.attempt) && receipt.attempt > 0 && receipt.attempt <= 5 && RECEIPT_STATUSES.includes(receipt.status)
    && ['shortcut', 'localApp'].includes(receipt.source) && timestamp(receipt.receivedAtMS) && noteValid(receipt.note);
}

export function receiveReceipt(run, receipt, now) {
  const reject = reason => ({ run, accepted: false, reason });
  if (!validateRun(run) || !timestamp(now) || !receiptValid(receipt)) return reject('invalid');
  if (receipt.executionID !== run.executionID) return reject('invalid');
  if (receipt.receivedAtMS > now || receipt.receivedAtMS < run.createdAtMS) return reject('invalid');
  const index = run.steps.findIndex(step => step.stepID === receipt.stepID);
  if (index < 0) return reject('invalid');
  const step = run.steps[index];
  if ((step.stepID === 'patrick-state') !== (receipt.source === 'localApp')) return reject('invalid');
  if (GOODNIGHT_STEPS.find(item => item.stepID === step.stepID).required && receipt.status === 'skipped') return reject('invalid');
  const existing = run.events.find(item => item.receiptID === receipt.receiptID);
  if (existing) return reject(Object.keys(existing).every(key => existing[key] === receipt[key]) ? 'duplicate' : 'invalid');
  if (receipt.attempt !== step.attempt || receipt.receivedAtMS < step.updatedAtMS) return reject('staleAttempt');
  if (step.status !== 'pending') return reject('alreadyResolved');
  const next = copy(run);
  next.steps[index] = { ...step, status: receipt.status, receiptID: receipt.receiptID, source: receipt.source, note: receipt.note, updatedAtMS: receipt.receivedAtMS };
  next.updatedAtMS = Math.max(run.updatedAtMS, receipt.receivedAtMS);
  next.events.push(copy(receipt));
  return { run: next, accepted: true, reason: 'applied' };
}

export function retryStep(run, stepID, now) {
  if (!validateRun(run) || !timestamp(now) || now < run.updatedAtMS) throw new Error('Invalid run or time');
  const index = run.steps.findIndex(step => step.stepID === stepID && step.status === 'failed' && step.attempt < 5);
  if (index < 0) return { run, attempt: null };
  const next = copy(run);
  next.steps[index] = { ...next.steps[index], status: 'pending', attempt: next.steps[index].attempt + 1, receiptID: null, source: null, note: null, updatedAtMS: now };
  next.updatedAtMS = now;
  return { run: next, attempt: next.steps[index].attempt };
}

export function retryFailed(run, now) {
  if (!validateRun(run) || !timestamp(now) || now < run.updatedAtMS) throw new Error('Invalid run or time');
  const retriedStepIDs = run.steps.filter(step => step.status === 'failed' && step.attempt < 5).map(step => step.stepID);
  let next = run;
  for (const stepID of retriedStepIDs) next = retryStep(next, stepID, now).run;
  return { run: next, retriedStepIDs };
}

export function summarize(run) {
  if (!validateRun(run)) throw new Error('Invalid run');
  const counts = Object.fromEntries(STATUSES.map(status => [status, run.steps.filter(step => step.status === status).length]));
  const complete = counts.pending === 0 && counts.failed === 0;
  const outcome = counts.failed ? 'needs-attention' : counts.pending ? 'awaiting-receipts' : counts.skipped ? 'completed-with-skips' : 'succeeded';
  return { ...counts, complete, outcome, watchFocusConfirmed: false };
}

export function restoreRun(serialized) {
  try { const run = JSON.parse(serialized); return validateRun(run) ? run : null; } catch { return null; }
}
