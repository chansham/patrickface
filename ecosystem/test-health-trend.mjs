import assert from 'node:assert/strict';
import fs from 'node:fs';
import { evaluateHealthTrends, companionInvitation } from './health-trend-core.js';
const fixtures = JSON.parse(fs.readFileSync(new URL('./health-trend-fixtures.json', import.meta.url)));
let checks = 0;
for (const test of fixtures.cases) {
  const before = JSON.stringify(test.input);
  const actual = evaluateHealthTrends(test.input);
  assert.deepEqual(actual, test.expected, `${test.id}: shared native/browser expected output`);
  assert.equal(JSON.stringify(test.input), before, `${test.id}: no input mutation`);
  const reordered = { ...test.input, points: [...test.input.points].reverse() };
  assert.deepEqual(evaluateHealthTrends(reordered), actual, `${test.id}: record order does not change meaning`);
  for (const result of actual) {
    if (result.state !== 'ready') { assert.equal(result.baseline, null); assert.equal(result.delta, null); }
    else { assert.ok(result.baselineCount >= 7); assert.ok(result.baselineCount <= 28); }
  }
  checks++;
}
// Invalid numeric/shape inputs cannot be serialized into JSON fixtures.
const ready = fixtures.cases.find(test => test.id === 'all-metrics').input;
for (const value of [NaN, Infinity, -Infinity]) {
  assert.ok(evaluateHealthTrends({ ...ready, nowMS: value }).every(result => result.reason === 'invalidInput'));
  const point = { ...ready.points[0], value };
  const results = evaluateHealthTrends({ ...ready, points: [point] });
  assert.equal(results.find(result => result.metric === point.metric).reason, 'invalidPoint'); checks++;
}
assert.ok(evaluateHealthTrends(null).every(result => result.reason === 'invalidInput'));
assert.ok(evaluateHealthTrends({ ...ready, points: null }).every(result => result.reason === 'invalidInput'));
assert.equal(companionInvitation('tired').mode, 'gentle');
assert.equal(companionInvitation('okay').mode, 'normal');
assert.equal(companionInvitation('unsure').mode, 'normal');
assert.deepEqual(companionInvitation('unexpected'), companionInvitation('unsure'));
// Self-report policy accepts no metric input: even contradictory demo records
// cannot alter the invitation chosen by the user.
for (const test of fixtures.cases) {
  evaluateHealthTrends(test.input);
  assert.equal(companionInvitation('tired').mode, 'gentle');
  assert.equal(companionInvitation('okay').mode, 'normal');
}
checks += 7;
console.log(`PASS ${fixtures.cases.length} shared health-trend fixtures; ${checks} checks (Swift execution remains separate).`);
