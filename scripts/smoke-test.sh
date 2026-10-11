#!/bin/bash
# Launches the real app and checks that its audio engine works end to end:
# it starts, plays a note pattern with sound, and suspends its audio context when idle.
# Unit tests cannot catch WebKit-only failures, such as the engine not starting at all.
# Usage: scripts/smoke-test.sh   (exit code 0 when every check passes)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT

"$ROOT/scripts/build-app.sh" debug > /dev/null
echo '{"song":{"title":"Smoke","bpm":120,"layers":[]},"chat":[]}' > "$WORK/session.json"

read -r -d '' SCRIPT <<'JS' || true
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ctx = strudel.getAudioContext();
const out = {};
await sleep(3500);
out.idle = ctx.state;
await window.vamp.play('setcps(0.5);\nnote("c3*4").s("sawtooth")');
await sleep(1500);
out.playing = ctx.state;
window.vamp.level();
await sleep(1500);
out.level = window.vamp.level().peak;
window.vamp.stop();
await sleep(4000);
out.stopped = ctx.state;
return JSON.stringify(out);
JS

VAMP_SESSION="$WORK/session.json" VAMP_JS="$SCRIPT" \
  "$ROOT/build/Vamp.app/Contents/MacOS/Vamp" > "$WORK/log" 2>&1 &
PID=$!
for _ in $(seq 1 60); do grep -q '^\[js\]\|fatal' "$WORK/log" && break; sleep 1; done
kill "$PID" 2>/dev/null || true

RESULT="$(grep '^\[js\]' "$WORK/log" | sed 's/^\[js\] //' || true)"
if [ -z "$RESULT" ]; then
  echo "FAIL: the engine did not report. Log:"; cat "$WORK/log"; exit 1
fi
python3 - "$RESULT" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
checks = {
    "audio context suspended while idle": r["idle"] == "suspended",
    "audio context running while playing": r["playing"] == "running",
    "the pattern makes sound (peak > 0.05)": r["level"] > 0.05,
    "audio context suspended after stop": r["stopped"] == "suspended",
}
for name, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + name)
sys.exit(0 if all(checks.values()) else 1)
PY
