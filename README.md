# Vamp

Vamp is a macOS app that makes music from prompts. You describe a change in plain words. An agent edits the song, and Vamp plays it straight away. Every layer is visible as a score and as code, so you can see what changed and adjust it by hand.

![Vamp playing a song with drums, bass and a pad](docs/screenshot.png)

## What it does

- **Score view.** Each layer is a lane. Melodic layers show a piano roll. Drum layers show one row per sound. A playhead moves across all lanes, and the notes under it light up.
- **Layers.** Each layer has its own name, role, volume, mute and solo controls.
- **Code.** Select a layer to see its [Strudel](https://strudel.cc) code. Edits play as soon as the code runs. If the code breaks, the last working version keeps playing, and the error shows under the editor.
- **Sections.** A song can have sections, such as Intro, Verse, Chorus, Breakdown and Outro. Each section has a length in bars and its own set of layers. A layer can also have different code in one section. The strip above the lanes shows the arrangement. Click a section to edit it, or turn on Loop to play and show only that section.
- **Agent.** Type a request such as "add a shuffling hi-hat groove". The agent returns only the edits it needs: add, change or remove a layer or section, or set the tempo. Vamp checks the new code before it plays. If the code fails, Vamp sends the errors back once for a fix. A request for a whole song ("compose…") uses the composer model with more thinking time.
- **Sounds.** Vamp loads the sample packs strudel.cc uses: 71 classic drum machines (TR-808, TR-909, LinnDrum and more), a Steinway piano, 128 orchestral and world instruments, and the Dirt samples, plus Strudel's synths and 125 General MIDI soundfont instruments (strings, brass, guitars, electric pianos, choirs, pads).
- **Transport.** A song with sections plays once and stops after its ending. Click a bar in the ruler to play from there, double-click a section to play it, or use the previous and next section buttons (← →). The clock shows the time and the current section.
- **Undo.** Every agent change has its own Undo button. ⌘Z and ⇧⌘Z move through all versions of the song.
- **Export.** "Copy code" copies the whole song as one Strudel program that runs on strudel.cc.

## Agent backends

Choose the backend from the menu in the prompt box or in Settings (⌘,).

| Backend | Needs | Cost |
|---|---|---|
| Claude subscription | The `claude` CLI, signed in | Included in your Claude plan |
| ChatGPT subscription | The `codex` CLI, signed in | Included in your ChatGPT plan |
| Anthropic API key | A key, stored in the login keychain | Pay per request. The log shows the cost of each prompt. |

Quick edits use the model you choose. The default is Claude Haiku, the cheapest choice. A request for a whole song ("compose…") uses Claude Opus with more thinking time. With Codex, it uses your Codex default model. Each request sends only the current song as JSON, a short summary of the last four prompts and the new request. A typical prompt uses about 5k tokens with the Claude CLI. The Codex CLI adds its own agent prompt, so it uses about 25k tokens.

Vamp looks for the CLIs in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` and some other common install folders.

## Build and run

You need macOS 14 or later and Xcode 16 or later.

```bash
scripts/build-app.sh          # builds build/Vamp.app (release)
open build/Vamp.app
```

The first start downloads the drum and instrument samples from the [Dirt-Samples](https://github.com/tidalcycles/Dirt-Samples) repository. Without a network, the synths still play, but sample layers show an "Unknown sound" error.

Shortcuts: Space plays and stops, and ← and → jump between sections, when no text field has focus. Return or ⌘↩ sends the prompt. ⌥⌘↩ plays and stops from anywhere.

## Tests

```bash
swift test                          # song model, edit plans, backend parsers, agent repair loop
node --test Tests/engine/*.test.mjs # the Strudel bridge: analysis, chord and sound checks
```

## How it fits together

- `Sources/VampCore`: the song model, the edit plan schema, the agent prompt, the output parsers and the repair loop. It has no UI code and full unit tests.
- `Sources/Vamp`: the SwiftUI app. `Engine/StrudelEngine.swift` hosts Strudel in a hidden web view. `Agent/` runs the three backends.
- `Resources/engine`: `engine.js` connects Swift to Strudel. `strudel.js` is the `@strudel/web` 1.3.0 bundle.

### Developer hooks

The app reads these environment variables at launch. Use them for checks without a mouse:

```bash
VAMP_PLAY=1 VAMP_PROMPT="make it darker" VAMP_SNAPSHOT=/tmp/vamp.png VAMP_SNAPSHOT_DELAY=30 \
  build/Vamp.app/Contents/MacOS/Vamp
```

`VAMP_SESSION=/tmp/test.json` keeps a test run away from your saved session. `VAMP_PROMPTS=/path/prompts.txt` sends each line of a file in order, each after the previous one finishes. `VAMP_QUIT=1` quits once the agent has finished and the session is saved; `VAMP_DONE_FILE=/path` writes that file instead and keeps the window open. `VAMP_SEEK=bar` moves the play cursor. `VAMP_SELECT` selects a layer by id. The full list is in `Sources/Vamp/DevHooks.swift`.

## Licence

Vamp is free software under the [GNU AGPL-3.0](LICENSE). It bundles [Strudel](https://codeberg.org/uzu/strudel), which has the same licence.
