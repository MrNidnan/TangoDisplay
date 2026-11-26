#!/usr/bin/env bash
# Usage: ./Install.sh [--build-only | --destination /path/TangoDisplay.app] [--no-launch]
set -euo pipefail

APP_NAME="TangoDisplay"
BUNDLE_ID="com.local.tangodisplay"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/$APP_NAME.app"
BUILD_ONLY=false
LAUNCH=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only) BUILD_ONLY=true; shift ;;
    --no-launch) LAUNCH=false; shift ;;
    --destination)
      [[ $# -ge 2 && "$2" == *.app ]] || { echo "Expected an .app path after --destination" >&2; exit 2; }
      DEST="$2"
      [[ "$DEST" == /* ]] || DEST="$PWD/$DEST"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./Install.sh [--build-only | --destination /path/TangoDisplay.app] [--no-launch]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

cd "$ROOT_DIR"
PACKAGE_DIR="$ROOT_DIR"
if "$BUILD_ONLY"; then PACKAGE_DIR="$ROOT_DIR/.build/package"; fi
mkdir -p "$PACKAGE_DIR"
STAGING="$(mktemp -d "$PACKAGE_DIR/.tangodisplay-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP_DIR="$STAGING/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "== Build (Release, universal) =="
swift build --only-use-versions-from-resolved-file -c release --triple arm64-apple-macosx13.0
swift build --only-use-versions-from-resolved-file -c release --triple x86_64-apple-macosx13.0
ARM_BIN="$(swift build --show-bin-path -c release --triple arm64-apple-macosx13.0)/$APP_NAME"
INTEL_BIN="$(swift build --show-bin-path -c release --triple x86_64-apple-macosx13.0)/$APP_NAME"
mkdir -p "$MACOS_DIR" "$RES_DIR"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$MACOS_DIR/$APP_NAME"

cp "icon.icns" "Sources/TangoDisplay/Resources/SetlistLogo.png" "$RES_DIR/"
ditto "Sources/TangoDisplay/Resources/RemoteUI" "$RES_DIR/RemoteUI"

echo "== Write Info.plist =="
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
  <key>CFBundleVersion</key>
  <string>114</string>
  <key>CFBundleShortVersionString</key>
  <string>4.0.1</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <!-- Required for reading track data via AppleScript (Music.app, Embrace) -->
  <key>NSAppleEventsUsageDescription</key>
  <string>TangoDisplay reads the currently playing track from Music.app, Swinsian, or Embrace to show it on the dancer display.</string>
  <!-- Required for receiving drags of iTunes-purchased tracks from Music.app -->
  <key>NSAppleMusicUsageDescription</key>
  <string>TangoDisplay needs access to your Apple Music library so tracks dragged from Music.app can be added to your setlist.</string>
  <!-- Required for global hotkeys (⌘⇧O/P/R) -->
  <key>NSInputMonitoringUsageDescription</key>
  <string>TangoDisplay uses global keyboard shortcuts so you can trigger overrides and pauses without switching windows.</string>
  <!-- Required for built-in microphone room noise monitoring (decibel meter) -->
  <key>NSMicrophoneUsageDescription</key>
  <string>TangoDisplay monitors the microphone to measure room noise so you can see whether music is too quiet, perfect, or too loud for the dance floor.</string>
  <!-- Required for the Setlist Remote feature so a phone on the same Wi-Fi can connect (Bonjour advertise + accept incoming HTTP/WebSocket) -->
  <key>NSLocalNetworkUsageDescription</key>
  <string>TangoDisplay hosts a small web page on this network so an iPhone can adjust volume and other sound controls from the dance floor.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_http._tcp</string>
  </array>
  <!-- Sparkle auto-update -->
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/richardsladetdj-creator/TangoDisplay/main/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>BUHKUUjLMvf3imY9/qbRJiES6Vq7/C3w94lkRB37CJw=</string>
</dict>
</plist>
EOF

echo "== Embed Sparkle framework =="
SPARKLE_FW="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "ERROR: Sparkle framework not found at $SPARKLE_FW"
  echo "       Run: swift package resolve"
  exit 1
fi
mkdir -p "$CONTENTS/Frameworks"
cp -R "$SPARKLE_FW" "$CONTENTS/Frameworks/"

echo "== Sign and verify bundle =="
codesign --force --deep --sign - "$CONTENTS/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP_DIR"
bash Scripts/VerifyBundle.sh "$APP_DIR"

PACKAGE="$PACKAGE_DIR/$APP_NAME.app"
bash Scripts/InstallBundle.sh "$APP_DIR" "$PACKAGE"
echo "Packaged: $PACKAGE"
if "$BUILD_ONLY"; then exit 0; fi

if [[ "$DEST" != "$PACKAGE" ]]; then
  bash Scripts/InstallBundle.sh "$PACKAGE" "$DEST"
fi
echo "Installed: $DEST"
if "$LAUNCH"; then open "$DEST"; fi
