#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="TAVIMeasurementPlugin"
BUILD_DIR="$ROOT/build"
OBJ_DIR="$BUILD_DIR/obj"
MODULE_CACHE="$BUILD_DIR/module-cache"
BUNDLE="$BUILD_DIR/${PLUGIN_NAME}.osirixplugin"
CONTENTS="$BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

HOROS_APP="/Applications/Horos.app"
HOROS_FRAMEWORKS="$HOROS_APP/Contents/Frameworks"
HOROS_HEADERS="$HOROS_FRAMEWORKS/Horos.framework/Versions/A/Headers"
HOROS_LOADER="$HOROS_APP/Contents/MacOS/Horos"

mkdir -p "$OBJ_DIR" "$MODULE_CACHE" "$MACOS_DIR" "$RESOURCES_DIR"
find "$OBJ_DIR" -name '*.o' -delete 2>/dev/null || true

COMMON_FLAGS=(
  -fobjc-arc
  -fmodules
  -fmodules-cache-path="$MODULE_CACHE"
  -Wall
  -Wextra
  -Wno-deprecated-declarations
  -mmacosx-version-min=11.0
  -I"$ROOT/src"
  -I"$HOROS_HEADERS"
  -F"$HOROS_FRAMEWORKS"
)

SOURCES=(
  "$ROOT/src/TAVITypes.m"
  "$ROOT/src/TAVIGeometry.m"
  "$ROOT/src/TAVIMeasurementSession.m"
  "$ROOT/src/TAVIProjectionPreviewView.m"
  "$ROOT/src/TAVIPlanningWindowController.m"
  "$ROOT/src/TAVIMeasurementPlugin.m"
)

for source in "${SOURCES[@]}"; do
  object="$OBJ_DIR/$(basename "${source%.m}.o")"
  clang "${COMMON_FLAGS[@]}" -c "$source" -o "$object"
done

clang "${COMMON_FLAGS[@]}" \
  -bundle \
  -bundle_loader "$HOROS_LOADER" \
  -o "$MACOS_DIR/$PLUGIN_NAME" \
  "$OBJ_DIR"/*.o \
  -framework Cocoa \
  -framework Horos \
  -framework UniformTypeIdentifiers

cp "$ROOT/resources/Info.plist" "$CONTENTS/Info.plist"

echo "Built plugin bundle:"
echo "  $BUNDLE"
