#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
toolchain="${SESTRIA_ANDROID_TOOLS:-/tmp/sestria-android-tools}"
godot_bin="${SESTRIA_GODOT:-$toolchain/godot}"
signing_dir="${SESTRIA_SIGNING_DIR:-$project_dir/../build/android/signing}"
if [[ ! -f "$signing_dir/sestria-release.keystore" || ! -f "$signing_dir/password.txt" ]]; then
  echo 'Imposta SESTRIA_SIGNING_DIR sulla cartella della chiave release esistente.' >&2
  exit 1
fi
if [[ -z "${JAVA_HOME:-}" ]]; then
  export JAVA_HOME
  JAVA_HOME="$(/usr/libexec/java_home -v 21)"
fi
mkdir -p build/android android/build/src/main/java/com/sestria/platform
cp native/*.java android/build/src/main/java/com/sestria/platform/
mkdir -p android/build/res/xml
cp native/sestria_update_paths.xml android/build/res/xml/
export GRADLE_USER_HOME="${SESTRIA_GRADLE_HOME:-/tmp/sestria-android-tools/gradle-home}"
export ANDROID_HOME="$toolchain/sdk"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$signing_dir/sestria-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=orlog
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$signing_dir/password.txt")"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
"$godot_bin" --headless --log-file "$project_dir/build/android/export.log" --path "$project_dir" --export-release "Android Mobile Saga"
apk_path="$(python3 -c 'import configparser; p=configparser.ConfigParser(); p.read("export_presets.cfg"); print(p["preset.0"]["export_path"].strip(chr(34)))')"
"$toolchain/sdk/build-tools/35.0.1/apksigner" verify --verbose "$apk_path"
"$toolchain/sdk/build-tools/35.0.1/zipalign" -c -P 16 4 "$apk_path"
(
  cd "$(dirname "$apk_path")"
  shasum -a 256 "$(basename "$apk_path")" > SHA256SUMS.txt
)
