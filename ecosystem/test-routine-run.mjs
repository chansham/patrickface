import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRun, receiveReceipt, retryStep, retryFailed, summarize, restoreRun, validateRun } from './routine-run-core.js';

const fixtures = JSON.parse(fs.readFileSync(new URL('./routine-run-fixtures.json', import.meta.url)));
let checks = 0;
for (const test of fixtures.cases) {
  let run = createRun({ executionID: fixtures.executionID, now: fixtures.createdAtMS });
  for (const operation of test.operations) {
    const previous = JSON.stringify(run);
    if (operation.type === 'receipt') {
      const result = receiveReceipt(run, operation.receipt, operation.atMS);
      assert.equal(result.reason, operation.result, test.name);
      assert.equal(JSON.stringify(run), previous, `${test.name}: immutable input`);
      if (!result.accepted) assert.equal(JSON.stringify(result.run), previous, `${test.name}: rejected receipt no change`);
      run = result.run;
    } else if (operation.type === 'retry') {
      const result = retryStep(run, operation.stepID, operation.atMS);
      assert.equal(result.attempt, operation.attempt, test.name); run = result.run;
    } else if (operation.type === 'restore') {
      run = restoreRun(JSON.stringify(run)); assert.ok(run, `${test.name}: restore`);
    }
    assert.ok(validateRun(run), `${test.name}: valid state after ${operation.type}`);
    assert.equal(summarize(run).watchFocusConfirmed, false, `${test.name}: never infer Watch Focus`);
    checks++;
  }
  const result = summarize(run);
  for (const [key, value] of Object.entries(test.expected)) assert.equal(result[key], value, `${test.name}: ${key}`);
  assert.equal(result.complete, result.pending === 0 && result.failed === 0, `${test.name}: honest summary`);
}
let run = createRun({ executionID: fixtures.executionID, now: 1000 });
for (const field of ['status', 'attempt', 'receiptID']) {
  const invalid = structuredClone(run); invalid.steps[0][field] = field === 'status' ? 'succeeded' : field === 'attempt' ? 2 : fixtures.executionID;
  assert.equal(restoreRun(JSON.stringify(invalid)), null, `malformed pending ${field}`); checks++;
}
assert.equal(restoreRun('{broken'), null); checks++;
assert.equal(restoreRun(JSON.stringify({ ...run, schemaVersion: 2 })), null); checks++;
const malformed = structuredClone(run); malformed.steps[0].source = 'shortcut';
assert.equal(restoreRun(JSON.stringify(malformed)), null); checks++;
const failedPreset = fixtures.cases.find(item => item.name === 'failed-only-retry-with-stale-receipt').operations.slice(0, 4);
for (const operation of failedPreset) run = receiveReceipt(run, operation.receipt, operation.atMS).run;
const before = structuredClone(run), retried = retryFailed(run, 1200);
assert.deepEqual(retried.retriedStepIDs, ['home-scene']);
assert.deepEqual(retried.run.steps.slice(0, 3), before.steps.slice(0, 3));
assert.equal(retried.run.executionID, before.executionID);
assert.equal(retried.run.steps[3].stepID, before.steps[3].stepID);
assert.equal(retried.run.steps[3].attempt, 2);
assert.equal(summarize(retried.run).complete, false); checks++;
console.log(`PASS ${fixtures.cases.length} shared routine scenarios and ${checks} operation/guard checks`);
