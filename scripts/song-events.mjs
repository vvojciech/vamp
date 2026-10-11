// Writes the note events of a saved Vamp song, using the real Strudel engine.
// Usage: node scripts/song-events.mjs session.json > events.json
// Then:  SCORE_SESSION=session.json SCORE_EVENTS=events.json swift test --filter ScoreReport
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Strudel logs a banner; keep stdout for the JSON only.
console.log = (...args) => console.error(...args);
const noop = () => {};
globalThis.window = globalThis;
globalThis.addEventListener = noop;
globalThis.removeEventListener = noop;
globalThis.document = { addEventListener: noop, removeEventListener: noop, dispatchEvent: noop, querySelector: () => null };

const root = new URL('../Resources/engine/', import.meta.url);
vm.runInThisContext(readFileSync(new URL('strudel.js', root), 'utf8'));
await globalThis.strudel.evalScope(globalThis.strudel);
vm.runInThisContext(readFileSync(new URL('engine.js', root), 'utf8'));

const { song } = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const sections = song.sections ?? [];

// Same arrangement as Song.program(for:) in Swift.
function program(layer) {
  if (sections.length === 0) return layer.code;
  if (!sections.some((s) => s.layerIDs.includes(layer.id))) return 'silence';
  const rows = sections.map((s) => {
    if (!s.layerIDs.includes(layer.id)) return `  [${s.bars}, silence]`;
    return `  [${s.bars}, (\n${s.variations[layer.id] ?? layer.code}\n  )]`;
  });
  return `arrange(\n${rows.join(',\n')}\n)`;
}

const bars = sections.reduce((n, s) => n + s.bars, 0) || 4;
const results = globalThis.vamp.analyze(song.layers.map((l) => ({ id: l.id, code: program(l) })), bars);
const events = {};
for (const r of results) {
  if (r.error) console.error(`${r.id}: ${r.error}`);
  else events[r.id] = r.events;
}
process.stdout.write(JSON.stringify({ bars, events }));
