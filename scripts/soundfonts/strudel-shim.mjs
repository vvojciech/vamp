// The soundfont package imports from @strudel/core and @strudel/webaudio. Both are already
// loaded as the global `strudel` bundle, so map the imports onto it instead of a second copy.
export const {
  freqToMidi, noteToMidi, getSoundIndex, Pattern, getPlayableNoteValue, registerSound,
  getADSRValues, getAudioContext, getParamADSR, getVibratoOscillator, getPitchEnvelope,
  onceEnded, releaseAudioNode,
} = globalThis.strudel;
