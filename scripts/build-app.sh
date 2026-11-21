#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Velora"
BUNDLE_ID="${VELORA_BUNDLE_ID:-com.kobenguyent.velora}"
VERSION="${VELORA_VERSION:-1.0.0}"
BUILD_NUMBER="${VELORA_BUILD_NUMBER:-1}"
GITHUB_REPO="${GITHUB_REPOSITORY:-${VELORA_GITHUB_REPO:-kobenguyent/Velora}}"
ARCH_MODE="native"
SIGN_IDENTITY="${APPLE_SIGNING_IDENTITY:--}"
OUTPUT_DIR="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH_MODE="$2"; shift 2 ;;
        --version)
            VERSION="${2#v}"; shift 2 ;;
        --build)
            BUILD_NUMBER="$2"; shift 2 ;;
        --github-repo)
            GITHUB_REPO="$2"; shift 2 ;;
        --sign-identity)
            SIGN_IDENTITY="$2"; shift 2 ;;
        --output-dir)
            OUTPUT_DIR="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

echo "==> Building $APP_NAME v$VERSION (build $BUILD_NUMBER) [arch=$ARCH_MODE, repo=$GITHUB_REPO]"

cd "$ROOT_DIR"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# 1. Compile executable (separate arm64 + x86_64 slices merged via lipo works with both Xcode & CommandLineTools)
if [[ "$ARCH_MODE" == "universal" ]]; then
    echo "==> Compiling arm64 release slice..."
    swift build -c release --arch arm64
    ARM64_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

    echo "==> Compiling x86_64 release slice..."
    swift build -c release --arch x86_64
    X86_64_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME"

    if [[ ! -f "$ARM64_BIN" || ! -f "$X86_64_BIN" ]]; then
        echo "Error: missing compiled architecture slice ($ARM64_BIN / $X86_64_BIN)" >&2
        exit 1
    fi

    echo "==> Creating universal Mach-O binary via lipo..."
    lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
else
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
    BINARY_PATH="$BIN_DIR/$APP_NAME"
    if [[ ! -f "$BINARY_PATH" ]]; then
        echo "Error: compiled binary not found at $BINARY_PATH" >&2
        exit 1
    fi
    cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 2. Generate AppIcon.icns
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swift "$SCRIPT_DIR/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

# 3. Stamp Info.plist from template
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
sed \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    -e "s|__GITHUB_REPO__|$GITHUB_REPO|g" \
    "$ROOT_DIR/Resources/Info.plist.template" > "$INFO_PLIST"

plutil -lint "$INFO_PLIST"

# 4. Write PkgInfo
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 5. Strip any extended attributes before signing
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# 6. Code sign:
#    - Default "-" performs ad-hoc signing (requires NO Apple Developer account and works on Apple Silicon + Intel).
#    - If a real Developer ID certificate is supplied, automatically enables hardened runtime & timestamping.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc signing $APP_BUNDLE (no Apple Developer account required)"
    codesign --force --deep --sign - "$APP_BUNDLE"
elif [[ "$SIGN_IDENTITY" == *"Developer ID"* ]]; then
    echo "==> Signing $APP_BUNDLE with Developer ID: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "==> Signing $APP_BUNDLE with local certificate: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Built app bundle successfully: $APP_BUNDLE"
file "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
