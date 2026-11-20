#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
toolchain="${SESTRIA_ANDROID_TOOLS:-/tmp/sestria-android-tools}"
godot_bin="${SESTRIA_GODOT:-godot}"
if [[ -x "$toolchain/godot" && -z "${SESTRIA_GODOT:-}" ]]; then
  godot_bin="$toolchain/godot"
fi
if [[ -z "${JAVA_HOME:-}" ]]; then
  export JAVA_HOME
  JAVA_HOME="$(/usr/libexec/java_home -v 21)"
fi

mkdir -p build/android/signing
if [[ ! -f build/android/signing/sestria-release.keystore ]]; then
  python3 - <<'PY'
import os, secrets
from pathlib import Path
p = Path('build/android/signing/password.txt')
if not p.exists():
    p.write_text(secrets.token_hex(24) + '\n')
os.chmod(p, 0o600)
PY
  "$JAVA_HOME/bin/keytool" -genkeypair \
    -keystore build/android/signing/sestria-release.keystore \
    -storepass:file build/android/signing/password.txt \
    -keypass:file build/android/signing/password.txt \
    -alias orlog -keyalg RSA -keysize 3072 -validity 10000 \
    -dname 'CN=Sestria,O=Sestria,C=IT'
  chmod 600 build/android/signing/sestria-release.keystore
fi

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$project_dir/build/android/signing/sestria-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=orlog
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat build/android/signing/password.txt)"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

"$godot_bin" --headless --log-file "$project_dir/build/android/export.log" \
  --path "$project_dir" --export-release "Android Portrait"

if [[ -x "$toolchain/sdk/build-tools/35.0.1/apksigner" ]]; then
  "$toolchain/sdk/build-tools/35.0.1/apksigner" verify --verbose build/android/Sestria-v3.2-Android.apk
  "$toolchain/sdk/build-tools/35.0.1/zipalign" -c -P 16 4 build/android/Sestria-v3.2-Android.apk
fi
shasum -a 256 build/android/Sestria-v3.2-Android.apk > build/android/SHA256SUMS.txt
echo "APK: $project_dir/build/android/Sestria-v3.2-Android.apk"
