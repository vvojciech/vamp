// Exposes Strudel's General MIDI soundfonts to engine.js, on top of the @strudel/web bundle.
import { registerSoundfonts } from '@strudel/soundfonts';
globalThis.vampRegisterSoundfonts = registerSoundfonts;
