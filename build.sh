#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/work/build"
CACHE_DIR="$PROJECT_DIR/work/module-cache"
APP_DIR="$PROJECT_DIR/outputs/清清 Mac.app"
VERIFIED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -d "$VERIFIED_SDK" ]]; then
  DEFAULT_SDK="$VERIFIED_SDK"
else
  DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi
SDK_PATH="${SDK_PATH:-$DEFAULT_SDK}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
if [[ "$TARGET_ARCH" != "arm64" && "$TARGET_ARCH" != "x86_64" ]]; then
  echo "Unsupported architecture: $TARGET_ARCH" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR" "$CACHE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
CLANG_MODULE_CACHE_PATH="$CACHE_DIR" swiftc -O -parse-as-library \
  -sdk "$SDK_PATH" -target "$TARGET_ARCH-apple-macosx14.0" \
  -module-cache-path "$CACHE_DIR" \
  "$PROJECT_DIR"/Sources/QingMac/*.swift \
  -o "$BUILD_DIR/QingMac"
cp "$BUILD_DIR/QingMac" "$APP_DIR/Contents/MacOS/QingMac"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
