// Vamp's bridge between Swift and Strudel. Swift calls window.vamp.*; results go back
// through the "vamp" message handler. Kept free of DOM work so Node can test it.
(() => {
  const S = globalThis.strudel;
  const post = (message) => globalThis.webkit?.messageHandlers?.vamp?.postMessage(message);
  // Enough for 16th-note hats across a 96-bar song.
  const MAX_EVENTS = 6000;
  const PACKS = 'https://raw.githubusercontent.com/felixroos/dough-samples/main';
  const SAMPLE_PACKS = [
    'github:tidalcycles/dirt-samples',
    `${PACKS}/tidal-drum-machines.json`,
    `${PACKS}/piano.json`,
    `${PACKS}/vcsl.json`,
    `${PACKS}/EmuSP12.json`,
    `${PACKS}/mridangam.json`,
  ];
  let repl = null;
  let knownSounds = null;

  function patternFor(code) {
    const { output } = S.transpiler(code, { wrapAsync: false, addReturn: true });
    const pattern = new Function(output)();
    if (!pattern || typeof pattern.queryArc !== 'function') {
      throw new Error('This code does not make a pattern.');
    }
    return pattern;
  }

  function toMidi(value) {
    if (value == null) return null;
    if (typeof value === 'number') return value;
    try { return S.noteToMidi(String(value)); } catch { return null; }
  }

  function describe(hap) {
    const v = hap.value;
    const obj = typeof v === 'object' && v !== null ? v : { note: v };
    let midi = toMidi(obj.note);
    if (midi == null && typeof obj.freq === 'number') midi = 69 + 12 * Math.log2(obj.freq / 440);
    const sound = obj.s != null ? String(obj.s) + (obj.n != null && midi == null ? `:${obj.n}` : '') : null;
    return {
      begin: hap.whole.begin.valueOf(),
      end: hap.whole.end.valueOf(),
      midi: midi == null || Number.isNaN(midi) ? null : Math.round(midi * 100) / 100,
      sound,
      // A drum-machine bank turns s("bd").bank("RolandTR909") into the sample "RolandTR909_bd".
      bank: obj.bank != null ? String(obj.bank) : null,
      gain: typeof obj.gain === 'number' ? obj.gain : 1,
    };
  }

  function unknownSound(events) {
    if (!knownSounds) return null;
    for (const e of events) {
      if (!e.sound) continue;
      const base = e.sound.split(':')[0];
      const name = e.bank ? `${e.bank}_${base}` : base;
      // Strudel stores sample names in lower case ("rolandtr909_bd").
      if (!knownSounds.has(name.toLowerCase())) {
        return e.bank ? `The bank "${e.bank}" has no sound "${base}".` : `Unknown sound "${base}".`;
      }
    }
    return null;
  }

  // Strudel only logs a warning for an unknown chord, so check the symbols up front.
  function unknownChord(code) {
    const known = S.voicingRegistry?.ireal?.dictionary;
    if (!known) return null;
    for (const match of code.matchAll(/chord\(\s*["'`]([^"'`]*)["'`]/g)) {
      for (const token of match[1].split(/[\s<>[\]{},|.@!?~*/:]+/)) {
        const symbol = /^[A-G][#b]?(.*)$/.exec(token);
        if (symbol && !(symbol[1] in known)) return `Unknown chord "${token}". Use symbols like C^7, Cm7, C7, Cm9.`;
      }
    }
    return null;
  }

  // Returns [{id, events} | {id, error}] for the first `cycles` bars of each layer.
  function analyze(layers, cycles) {
    return layers.map(({ id, code }) => {
      try {
        const chordError = unknownChord(code);
        if (chordError) return { id, error: chordError };
        const haps = patternFor(code).queryArc(0, cycles).filter((h) => h.whole && h.hasOnset());
        const events = haps.slice(0, MAX_EVENTS).map(describe);
        const soundError = unknownSound(events);
        return soundError ? { id, error: soundError } : { id, events };
      } catch (error) {
        return { id, error: String(error?.message ?? error) };
      }
    });
  }

  function setKnownSounds(names) {
    knownSounds = names ? new Set(names.map((n) => n.toLowerCase())) : null;
  }

  async function init() {
    try {
      repl = await S.initStrudel({
        // The same packs strudel.cc loads. Offline, the synths still work and
        // sample layers report an unknown sound.
        prebake: () => {
          // General MIDI soundfonts (gm_piano, gm_string_ensemble_1, ...) load lazily on first use.
          globalThis.vampRegisterSoundfonts?.();
          return loadSamplePacks();
        },
      });
      // Strudel registers its audio worklets (crush, coarse, shape, ...) only on the first mouse-down
      // in the page. Nobody clicks the hidden web view, so register them now; without them every
      // note that uses such an effect is dropped.
      await S.initAudio();
      setKnownSounds(Object.keys(S.soundMap.get()));
      post({ type: 'ready', sounds: knownSounds.size });
      post({ type: 'log', message: `ready with ${knownSounds.size} sounds` });
    } catch (error) {
      post({ type: 'fatal', message: String(error?.message ?? error) });
    }
  }

  function loadSamplePacks() {
    return Promise.all(SAMPLE_PACKS.map((pack) => S.samples(pack).catch((error) =>
      post({ type: 'log', message: `Samples did not load from ${pack}: ${error?.message ?? error}` }))));
  }

  async function play(code) {
    try {
      await S.getAudioContext().resume();
      await repl.evaluate(code, true);
      post({ type: 'playing' });
    } catch (error) {
      post({ type: 'playError', message: String(error?.message ?? error) });
    }
  }

  function stop() {
    repl?.stop();
    post({ type: 'stopped' });
  }

  /// Peak and RMS of what is playing now, 0 to 1. Zero means silence.
  function level() {
    const analyser = globalThis.vampAnalyser;
    if (!analyser) return { peak: 0, rms: 0 };
    const samples = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(samples);
    let peak = 0, sum = 0;
    for (const s of samples) { peak = Math.max(peak, Math.abs(s)); sum += s * s; }
    return { peak, rms: Math.sqrt(sum / samples.length) };
  }

  function now() {
    return repl?.scheduler?.started ? repl.scheduler.now() : null;
  }

  // Swift reads the clock at display rate; this keeps a coarse push for idle checks.
  const clock = setInterval(() => {
    const cycle = now();
    if (cycle != null) post({ type: 'time', cycle });
  }, 250);
  clock.unref?.();

  globalThis.vamp = { init, analyze, play, stop, now, level, setKnownSounds };
})();
