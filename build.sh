#!/bin/bash
# Baut MindMaps.app im Terminal – Alternative zu Xcode (⌘R).
# Aufruf:  ./build.sh          → baut nach build/MindMaps.app
#          ./build.sh --run    → baut und startet die App
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MindMaps.app"
BUNDLE_ID="de.leonardjaeger.MindMaps"
VERSION="0.1"
MIN_OS="15.0"
ARCH="$(uname -m)"

echo "→ Aufräumen"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

echo "→ Kompilieren (${ARCH}, ab macOS ${MIN_OS})"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
find MindMaps -name '*.swift' -print0 | xargs -0 xcrun --sdk macosx swiftc \
    -parse-as-library -O -swift-version 5 \
    -sdk "$SDK" -target "${ARCH}-apple-macos${MIN_OS}" \
    -module-name MindMaps \
    -o "$APP/Contents/MacOS/MindMaps"

echo "→ Ressourcen und Icon"
cp MindMaps/Resources/Themes.json "$APP/Contents/Resources/"
cp MindMaps/Assets.xcassets/AppIcon.appiconset/icon_*.png build/AppIcon.iconset/
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Info.plist"
PLIST="$APP/Contents/Info.plist"
cp Config/Info.plist "$PLIST"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
pb "Add :CFBundleExecutable string MindMaps"
pb "Add :CFBundleIdentifier string ${BUNDLE_ID}"
pb "Add :CFBundleName string MindMaps"
pb "Add :CFBundleDisplayName string MindMaps"
pb "Add :CFBundlePackageType string APPL"
pb "Add :CFBundleShortVersionString string ${VERSION}"
pb "Add :CFBundleVersion string 1"
pb "Add :CFBundleIconFile string AppIcon"
pb "Add :CFBundleDevelopmentRegion string de"
pb "Add :LSMinimumSystemVersion string ${MIN_OS}"
pb "Add :LSApplicationCategoryType string public.app-category.productivity"
pb "Add :NSHighResolutionCapable bool true"

echo "→ Signieren (lokal)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ Fertig: $APP"
if [[ "${1:-}" == "--run" ]]; then
    open "$APP"
fi
