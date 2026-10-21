import assert from 'node:assert/strict';
import fs from 'node:fs';
import { AftercarePolicy, AFTERCARE_VARIANTS } from './aftercare-core.js';

const fixtures = JSON.parse(fs.readFileSync(new URL('./aftercare-fixtures.json', import.meta.url)));
assert.equal(fixtures.schemaVersion, 1);
assert.ok(fixtures.cases.length >= 30);
assert.equal(new Set(fixtures.cases.map(test => test.id)).size, fixtures.cases.length);
let operations = 0, assertions = 0;
function run(policy, action) {
  switch (action.op) {
    case 'visibility': return policy.updateVisibility(action);
    case 'observe': return policy.observeActivity(action);
    case 'complete': return policy.receiveCompletion(action.event, action);
    case 'choose': return policy.choose(action.variant, action.nowMS);
    case 'finish': return policy.finish(action.nowMS);
    case 'tick': return policy.tick(action.nowMS);
    case 'dismiss': return policy.dismiss();
    case 'review': return policy.beginReview(action);
    default: throw Error(`Unknown fixture operation: ${action.op}`);
  }
}
// Catch accidental introduction of persisted health/activity state, sound, or
// background timers. A policy invocation must remain a pure memory transition.
let sideEffects = 0;
globalThis.localStorage = new Proxy({}, { get() { sideEffects++; throw Error('Unexpected storage access'); } });
globalThis.sessionStorage = globalThis.localStorage;
globalThis.fetch = () => { sideEffects++; throw Error('Unexpected network request'); };
globalThis.setTimeout = () => { sideEffects++; throw Error('Unexpected timer'); };
globalThis.setInterval = globalThis.setTimeout;
for (const test of fixtures.cases) {
  const policy = new AftercarePolicy();
  for (const [index, action] of test.actions.entries()) {
    const before = JSON.stringify(action);
    const actual = run(policy, action);
    assert.equal(JSON.stringify(action), before, `${test.id}: input mutation`);
    for (const [key, expected] of Object.entries(action.expected ?? {})) {
      assert.deepEqual(actual[key], expected, `${test.id} operation ${index}: ${key}`); assertions++;
    }
    assert.deepEqual(actual, policy.state);
    assert.ok(actual.availableVariants.every(id => AFTERCARE_VARIANTS.includes(id)));
    if (actual.phase === 'playing') assert.ok(actual.availableVariants.includes(actual.variant));
    // UI code cannot mutate the invitation by retaining the returned object.
    actual.availableVariants.push('invented'); actual.phase = 'playing';
    assert.ok(!policy.state.availableVariants.includes('invented'));
    operations++;
  }
}
for (const value of [NaN, Infinity, -Infinity, -1]) {
  const policy = new AftercarePolicy();
  policy.updateVisibility({active:true,nowMS:1000});
  policy.beginReview({kind:'exercise',nowMS:2000,availableVariants:['towel']});
  assert.equal(policy.choose('towel', value).phase, 'dismissed');
  assert.equal(policy.state.reason, 'invalidTime'); assertions += 2;
}
for (const endedAtMS of [NaN, Infinity, -Infinity]) {
  const policy = new AftercarePolicy();
  policy.updateVisibility({active:true,nowMS:1000});
  policy.observeActivity({id:'session',kind:'running',status:'running',nowMS:2000});
  assert.equal(policy.receiveCompletion({id:'session',kind:'running',status:'completed',endedAtMS},
    {nowMS:3000,availableVariants:['towel']}).reason,'invalidEvent'); assertions++;
}
assert.equal(sideEffects, 0);
console.log(`PASS ${fixtures.cases.length} shared aftercare scenarios, ${operations} operations, ${assertions} expected-state assertions; zero storage/network/timer side effects. Swift execution remains separate.`);
