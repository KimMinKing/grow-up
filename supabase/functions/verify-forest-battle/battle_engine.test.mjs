import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { simulateForestBattle } from './battle_engine.mjs';

const vectors = JSON.parse(readFileSync(new URL('./battle_vectors.json', import.meta.url),
  'utf8').replace(/^\uFEFF/, ''));

test('server combat kernel matches Dart battle outcomes', () => {
  assert.equal(vectors.length, 2622);
  for (const vector of vectors) {
    assert.deepEqual(simulateForestBattle(vector.stageId, vector.squad),
      vector.expected, JSON.stringify(vector.squad));
  }
});

test('combat kernel rejects unsupported and malformed input', () => {
  assert.throws(() => simulateForestBattle('unknown', Array(5).fill(null)));
  assert.throws(() => simulateForestBattle('__proto__', Array(5).fill(null)));
  assert.throws(() => simulateForestBattle('forest_moss_gate', []));
  assert.throws(() => simulateForestBattle('forest_moss_gate', [
    { speciesId: 'unknown', level: 1 }, null, null, null, null,
  ]));
  assert.throws(() => simulateForestBattle('forest_moss_gate', [
    { speciesId: '__proto__', level: 1 }, null, null, null, null,
  ]));
  assert.throws(() => simulateForestBattle('forest_moss_gate', [
    { speciesId: 'pine_fox', level: 7 }, null, null, null, null,
  ]));
});
