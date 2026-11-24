#!/bin/sh
# Compila M999Battery.app (universal arm64 + x86_64, sin Xcode) y, con --dmg, genera build/M999Battery-<versión>.dmg.
#   ./build.sh                       compila el .app (firma con "Apple Development" si existe, si no ad hoc)
#   ./build.sh --dmg                 además crea el DMG
#   VERSION=1.0.0 SIGN_IDENTITY=- ./build.sh --dmg      versión y firma explícitas (- = ad hoc)
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
VERSION=${VERSION:-1.0.0}
APP=M999Battery.app

rm -rf build "$APP"
mkdir -p "$APP/Contents/MacOS" build
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" main.swift -o "build/M999Battery-$arch"
done
lipo -create build/M999Battery-arm64 build/M999Battery-x86_64 -output "$APP/Contents/MacOS/M999Battery"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

# Con una identidad estable macOS conserva el permiso de Monitorización de entrada entre compilaciones.
if [ -n "$SIGN_IDENTITY" ]; then
    codesign -s "$SIGN_IDENTITY" --force "$APP"
else
    codesign -s "Apple Development" --force "$APP" 2>/dev/null || codesign -s - --force "$APP"
fi
"$APP/Contents/MacOS/M999Battery" --selftest   # corre la variante nativa de este Mac

if [ "$1" = "--dmg" ]; then
    # dmgbuild crea el DMG con fondo e iconos sin pasar por Finder (funciona igual en CI).
    [ -x .venv/bin/dmgbuild ] || { python3 -m venv .venv && .venv/bin/pip -q install "dmgbuild==1.6.5"; }
    .venv/bin/dmgbuild -s dmg/settings.py -D app="$PWD/$APP" -D bg="$PWD/dmg/background.tiff" \
        M999Battery "build/M999Battery-$VERSION.dmg"
    echo "DMG: build/M999Battery-$VERSION.dmg"
fi
echo "App: $APP (v$VERSION)"
