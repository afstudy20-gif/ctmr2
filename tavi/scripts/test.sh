#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
MODULE_CACHE="$BUILD_DIR/module-cache"
TEST_BIN="$BUILD_DIR/TAVIGeometryTests"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

clang \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$MODULE_CACHE" \
  -Wall \
  -Wextra \
  -mmacosx-version-min=11.0 \
  -I"$ROOT/src" \
  "$ROOT/src/TAVITypes.m" \
  "$ROOT/src/TAVIGeometry.m" \
  "$ROOT/tests/TAVIGeometryTests.m" \
  -framework Foundation \
  -o "$TEST_BIN"

"$TEST_BIN"
