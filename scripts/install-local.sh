#!/usr/bin/env bash
set -euo pipefail

# Builds Velora natively and installs it directly onto your MacBook Pro for local testing
# WITHOUT requiring a paid Apple Developer account.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Velora"
INSTALL_DIR="/Applications"
LAUNCH_AFTER=1
BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            INSTALL_DIR="$HOME/Applications"; shift ;;
        --no-launch)
            LAUNCH_AFTER=0; shift ;;
        *)
            BUILD_ARGS+=("$1"); shift ;;
    esac
done

# Auto-detect optional local self-signed certificate named "Velora Local Dev" in login Keychain
# (preserves macOS TCC permissions across rebuilds if user created one; otherwise ad-hoc "-" is used).
if [[ -z "${APPLE_SIGNING_IDENTITY:-}" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Velora Local Dev"'; then
        echo "==> Found local Keychain signing certificate 'Velora Local Dev'; using it."
        export APPLE_SIGNING_IDENTITY="Velora Local Dev"
    fi
fi

"$SCRIPT_DIR/build-app.sh" --arch native ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

# Fallback to ~/Applications if /Applications is not writable by current user
if [[ "$INSTALL_DIR" == "/Applications" && ! -w "/Applications" ]]; then
    echo "==> /Applications is not writable without sudo; installing into $HOME/Applications instead."
    INSTALL_DIR="$HOME/Applications"
fi

mkdir -p "$INSTALL_DIR"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"

# Gracefully close any running Velora instance before replacing
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Closing running $APP_NAME instance..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || pkill -TERM -x "$APP_NAME" || true
    for _ in {1..20}; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

echo "==> Installing $APP_NAME.app to $TARGET_APP"
rm -rf "$TARGET_APP"
ditto "$ROOT_DIR/dist/$APP_NAME.app" "$TARGET_APP"
xattr -cr "$TARGET_APP" 2>/dev/null || true

# Register with LaunchServices so Spotlight & Finder immediately show Velora + icon
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
fi

echo "==> Installed successfully: $TARGET_APP"

if [[ "$LAUNCH_AFTER" -eq 1 ]]; then
    echo "==> Launching $APP_NAME..."
    open -n "$TARGET_APP"
fi
