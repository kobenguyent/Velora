#!/usr/bin/env bash
set -euo pipefail

# Packages universal Velora.app into GitHub Release artifacts:
#   - Velora-<version>-macos-universal.zip  (used by in-app auto-updater)
#   - Velora-<version>-macos-universal.dmg  (drag-to-Applications installer)
#   - SHA256SUMS.txt                        (verified by in-app auto-updater via CryptoKit)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Velora"
VERSION="${VELORA_VERSION:-1.0.0}"
BUILD_NUMBER="${VELORA_BUILD_NUMBER:-1}"
ARCH_MODE="universal"
GITHUB_REPO="${GITHUB_REPOSITORY:-${VELORA_GITHUB_REPO:-kobenguyent/Velora}}"
OUTPUT_DIR="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2#v}"; shift 2 ;;
        --build)
            BUILD_NUMBER="$2"; shift 2 ;;
        --arch)
            ARCH_MODE="$2"; shift 2 ;;
        --github-repo)
            GITHUB_REPO="$2"; shift 2 ;;
        --output-dir)
            OUTPUT_DIR="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

"$SCRIPT_DIR/build-app.sh" \
    --arch "$ARCH_MODE" \
    --version "$VERSION" \
    --build "$BUILD_NUMBER" \
    --github-repo "$GITHUB_REPO" \
    --output-dir "$OUTPUT_DIR"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ARTIFACT_BASE="$APP_NAME-$VERSION-macos-$ARCH_MODE"
ZIP_PATH="$OUTPUT_DIR/$ARTIFACT_BASE.zip"
DMG_PATH="$OUTPUT_DIR/$ARTIFACT_BASE.dmg"
CHECKSUM_PATH="$OUTPUT_DIR/SHA256SUMS.txt"

# 1. Create macOS-faithful ZIP archive using `ditto` (preserves symlinks, permissions & signatures)
echo "==> Packaging ZIP: $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# 2. Create drag-to-Applications DMG using native `hdiutil`
echo "==> Packaging DMG: $DMG_PATH"
rm -f "$DMG_PATH"
DMG_STAGING="$(mktemp -d)"
trap 'rm -rf "$DMG_STAGING"' EXIT

ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

cat > "$DMG_STAGING/Install Note.txt" <<'EOF'
Velora for macOS — Quick Install
================================

1. Drag Velora.app into the Applications folder.
2. Because this open-source build is ad-hoc signed (no paid Apple Developer ID),
   macOS Gatekeeper may show a warning the first time you open it.

To allow Velora cleanly on macOS:
  • Open Terminal and run:
      xattr -dr com.apple.quarantine /Applications/Velora.app
  • Or open System Settings → Privacy & Security → scroll down → click "Open Anyway".

After the first launch, Velora's built-in GitHub Releases auto-updater handles
future updates automatically!
EOF

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# 3. Generate SHA256SUMS.txt for integrity verification & in-app updater validation
echo "==> Generating SHA256SUMS.txt"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "==> Release artifacts ready in $OUTPUT_DIR:"
ls -lh "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
cat "$CHECKSUM_PATH"
