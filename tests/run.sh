#!/bin/bash
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -I "$root/include" -I "$root/src" "$root/tests/get_bundle.m" \
  "$root/src/adapter/get.m" "$root/src/adapter/env.m" "$root/src/adapter/globals.m" \
  "$root/src/adapter/keys.m" "$root/src/adapter/now_playing.m" \
  "$root/src/private/MediaRemote.m" "$root/src/utility/helpers.m" \
  -o "$root/build/test-get-bundle"
python3 "$root/tests/get_bundle.py"
