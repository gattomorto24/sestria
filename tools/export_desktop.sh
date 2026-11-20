#!/bin/bash
# Esporta Sestria per macOS (universale, firma ad hoc) e Windows x64 e prepara gli archivi della release.
# Uso: tools/export_desktop.sh 4.5   (le versioni in project.godot ed export_presets.cfg devono già coincidere)
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Indica la versione, ad esempio 4.5}"
godot_bin="${SESTRIA_GODOT:-${SESTRIA_ANDROID_TOOLS:-/tmp/sestria-android-tools}/godot}"
release="build/release"
mkdir -p build/desktop/windows "$release"
rm -rf build/desktop/Sestria.app build/desktop/windows/Sestria.exe
"$godot_bin" --headless --path . --import >/dev/null 2>&1 || true
"$godot_bin" --headless --path . --export-release "macOS" >/dev/null 2>&1
"$godot_bin" --headless --path . --export-release "Windows x64" >/dev/null 2>&1
xattr -cr build/desktop/Sestria.app
# Nessun certificato Developer ID: firma ad hoc, senza notarizzazione.
codesign --force --deep --sign - --timestamp=none build/desktop/Sestria.app
codesign --verify --deep --strict build/desktop/Sestria.app
stage="$(mktemp -d)"
mac="Sestria-v$version-macOS-universal"
win="Sestria-v$version-Windows-x64"
mkdir -p "$stage/$mac" "$stage/$win"
cp -R build/desktop/Sestria.app "$stage/$mac/"
cp tools/desktop/LEGGIMI-macOS.txt "$stage/$mac/LEGGIMI.txt"
cp build/desktop/windows/Sestria.exe "$stage/$win/"
cp tools/desktop/LEGGIMI-Windows.txt "$stage/$win/LEGGIMI.txt"
rm -f "$release/$mac.zip" "$release/$win.zip"
(cd "$stage" && ditto -c -k --sequesterRsrc --keepParent "$mac" "$OLDPWD/$release/$mac.zip")
(cd "$stage" && COPYFILE_DISABLE=1 zip -r -X -q "$OLDPWD/$release/$win.zip" "$win")
rm -rf "$stage"
echo "Pacchetti in $release: $mac.zip, $win.zip"
