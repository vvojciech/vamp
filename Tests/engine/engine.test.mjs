// Runs the Strudel bridge in Node: `node --test Tests/engine`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';

const noop = () => {};
globalThis.window = globalThis;
globalThis.addEventListener = noop;
globalThis.removeEventListener = noop;
globalThis.document = { addEventListener: noop, removeEventListener: noop, dispatchEvent: noop, querySelector: () => null };

const root = new URL('../../Resources/engine/', import.meta.url);
vm.runInThisContext(readFileSync(new URL('strudel.js', root), 'utf8'));
await globalThis.strudel.evalScope(globalThis.strudel);
vm.runInThisContext(readFileSync(new URL('engine.js', root), 'utf8'));
const { analyze, setKnownSounds } = globalThis.vamp;
const starter = JSON.parse(readFileSync(new URL('starter.json', import.meta.url), 'utf8'));

test('drum events carry sounds and positions', () => {
  const [result] = analyze([{ id: 'd', code: 's("bd [~ sd]")' }], 1);
  assert.deepEqual(result.events.map((e) => [e.begin, e.end, e.sound]), [[0, 0.5, 'bd'], [0.75, 1, 'sd']]);
});

test('notes become midi numbers', () => {
  const [result] = analyze([{ id: 'b', code: 'note("c2 e2")' }], 1);
  assert.deepEqual(result.events.map((e) => e.midi), [36, 40]);
});

test('scale degrees and chord voicings produce notes', () => {
  const [scale, chords] = analyze([
    { id: 's', code: 'n("0 2 4").scale("C4:major")' },
    { id: 'c', code: 'chord("Cm7").voicing()' },
  ], 1);
  assert.deepEqual(scale.events.map((e) => e.midi), [60, 64, 67]);
  assert.ok(chords.events.length >= 3);
  assert.ok(chords.events.every((e) => e.midi != null));
});

test('syntax errors are reported per layer', () => {
  const results = analyze([{ id: 'ok', code: 's("bd")' }, { id: 'bad', code: 's("bd"' }], 1);
  assert.ok(results[0].events);
  assert.match(results[1].error, /./);
});

test('unknown sounds are reported once the sound list is known', () => {
  setKnownSounds(['bd', 'sawtooth']);
  const [bad, good] = analyze([{ id: 'k', code: 's("kick*4")' }, { id: 'b', code: 's("bd:3*2")' }], 1);
  setKnownSounds(null);
  assert.equal(bad.error, 'Unknown sound "kick".');
  assert.ok(good.events);
});

test('unknown chord symbols are errors, known ones pass', () => {
  const [bad, good] = analyze([
    { id: 'x', code: 'chord("<Cm9 Abmaj7>").voicing()' },
    { id: 'y', code: 'chord("<Cm9 Ab^7 F-7 Bb7sus [G7 G7b9]>").voicing()' },
  ], 1);
  assert.match(bad.error, /Abmaj7/);
  assert.ok(good.events);
});

test('arranged programs place each section in song time', () => {
  const code = 'arrange(\n  [2, silence],\n  [1, (\nnote("<c3 e3>")\n  )],\n  [1, (\nnote("g3")\n  )]\n)';
  const [result] = analyze([{ id: 'a', code }], 4);
  assert.deepEqual(result.events.map((e) => [e.begin, e.midi]), [[2, 48], [3, 55]]);
});

test('drum-machine banks are checked by their full sample name', () => {
  // Strudel keeps these names in lower case.
  setKnownSounds(['rolandtr909_bd', 'rolandtr909_sd']);
  const [good, bad] = analyze([
    { id: 'a', code: 's("bd sd").bank("RolandTR909")' },
    { id: 'b', code: 's("bd cb").bank("RolandTR909")' },
  ], 1);
  setKnownSounds(null);
  assert.ok(good.events);
  assert.equal(bad.error, 'The bank "RolandTR909" has no sound "cb".');
});

test('a song wrapped with a silent tail plays nothing in the tail', () => {
  const code = 'arrange(\n[4, stack(\n  (\narrange(\n  [4, (\nnote("c3")\n  )]\n)\n  ).postgain(0.80)\n)],\n[2, silence]\n)';
  const [result] = analyze([{ id: 'song', code }], 6);
  assert.deepEqual(result.events.map((e) => e.begin), [0, 1, 2, 3]);
});

test('the starter song analyses without errors', () => {
  const results = analyze(starter.layers, 4);
  for (const r of results) assert.equal(r.error, undefined, `${r.id}: ${r.error}`);
});
