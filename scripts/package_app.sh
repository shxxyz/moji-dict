#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-"$PROJECT_DIR/dist"}"
APP_NAME="Moji 辞書"
EXECUTABLE_NAME="MojiQuickLook"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME.zip"
SWIFT_MODULE_CACHE="$PROJECT_DIR/.build/module-cache"
CLANG_MODULE_CACHE="$PROJECT_DIR/.build/clang-cache"
ASSET_BUILD_DIR="$PROJECT_DIR/.build/asset-catalog"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PROJECT_DIR/Info.plist")"

# Swift 6.4's default swiftbuild backend can record the deployment target as
# the linked SDK (14.0), opting out of modern AppKit appearance. Use the native
# backend with the selected Xcode SDK until that backend regression is fixed.
BUILD_OPTIONS=(--package-path "$PROJECT_DIR" -c release --disable-sandbox
    --build-system native --sdk "$SDK_PATH")

mkdir -p "$SWIFT_MODULE_CACHE" "$CLANG_MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE"
swift build "${BUILD_OPTIONS[@]}"

BIN_DIR="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"
BUILD_INFO="$(xcrun vtool -show-build "$BIN_DIR/$EXECUTABLE_NAME")"
if ! awk -v sdk="$SDK_VERSION" -v minimum="$MINIMUM_MACOS" '
    function sameVersion(a, b, x, y, i) {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++) if ((x[i] + 0) != (y[i] + 0)) return 0
        return 1
    }
    $1 == "sdk" { sdkSeen++; if (!sameVersion($2, sdk)) bad = 1 }
    $1 == "minos" { minSeen++; if (!sameVersion($2, minimum)) bad = 1 }
    END { exit (bad || !sdkSeen || !minSeen) }
' <<< "$BUILD_INFO"; then
    print -u2 "Build metadata mismatch: expected SDK $SDK_VERSION, minimum macOS $MINIMUM_MACOS."
    print -u2 -- "$BUILD_INFO"
    exit 1
fi
print -- "$BUILD_INFO"

mkdir -p "$ASSET_BUILD_DIR"
xcrun actool "$PROJECT_DIR/assets/Assets.xcassets" \
    --compile "$ASSET_BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target "$MINIMUM_MACOS" \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_BUILD_DIR/asset-info.plist"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ASSET_BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ASSET_BUILD_DIR/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"

codesign --force --sign - --timestamp=none "$APP_BUNDLE"
rm -f "$ZIP_PATH"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "$APP_BUNDLE"
echo "$ZIP_PATH"
