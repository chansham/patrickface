import assert from 'node:assert/strict';
import fs from 'node:fs';
import { AutomationGate } from './automation-core.js';
const fixtures = JSON.parse(fs.readFileSync(new URL('../tools/fixtures/automation-events.json', import.meta.url)));
let checks = 0;
for (const item of fixtures.cases) {
  let gate = new AutomationGate();
  for (const step of item.steps) {
    if (step.type === 'presentation') gate.setPresentationActive(step.active, step.atMS);
    else if (step.type === 'restart') gate = new AutomationGate(gate.seen);
    else { const result = gate.consume(step.event, step.atMS); assert.equal(result.outcome, step.outcome, item.name); assert.equal(gate.seen.length, step.seenCount, item.name); checks += 2; }
  }
}
const gate = new AutomationGate(); gate.setPresentationActive(true, 1);
for (let i=0;i<101;i++) gate.consume({id:`00000000-0000-4000-8000-${String(i).padStart(12,'0')}`,kind:'wake-up',source:'manual',occurredAtMS:1},1);
assert.equal(gate.seen.length,100); assert.ok(gate.seen[0].endsWith('000000000001')); checks += 2;
for (const bad of [0,-1,NaN,Infinity]) { assert.equal(gate.consume({id:'00000000-0000-4000-8000-000000000111',kind:'wake-up',source:'manual',occurredAtMS:bad},10).outcome,'invalid'); checks++; }
console.log(`PASS ${checks} automation checks from ${fixtures.cases.length} shared scenarios plus invalid-time and bounded receipts`);
