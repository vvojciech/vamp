#!/bin/bash
# Builds Resources/engine/soundfonts.js from @strudel/soundfonts. Run it only to update the vendored file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
cp "$ROOT"/scripts/soundfonts/*.mjs "$WORK/"
cd "$WORK"
npm init -y >/dev/null
npm install --silent @strudel/soundfonts@1.3.0 esbuild@0.28.2
npx esbuild entry.mjs --bundle --format=iife --minify \
  --alias:@strudel/core=./strudel-shim.mjs --alias:@strudel/webaudio=./strudel-shim.mjs \
  --outfile="$ROOT/Resources/engine/soundfonts.js"
echo "$ROOT/Resources/engine/soundfonts.js"
