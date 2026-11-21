#!/bin/bash
# Genera i pacchetti contenuti di una release (macOS, Windows, Android) e il manifest firmato.
# Uso: tools/export_content_pack.sh 4.6
# Prerequisiti: content.json e mobile/content.json con "content" = versione; "min_base" = prima versione dell'app
# completa che può eseguire questi contenuti (alzalo quando cambia il motore Godot o il codice nativo/Java).
# La chiave privata di firma (RSA) sta fuori da Git: SESTRIA_CONTENT_KEY o build/content-signing/sestria-content-private.pem.
set -euo pipefail
cd "$(dirname "$0")/.."
project_dir="$(pwd)"
version="${1:?Indica la versione, ad esempio 4.6}"
godot_bin="${SESTRIA_GODOT:-${SESTRIA_ANDROID_TOOLS:-/tmp/sestria-android-tools}/godot}"
key="${SESTRIA_CONTENT_KEY:-}"
if [[ -z "$key" ]]; then
  for candidate in "$project_dir/build/content-signing/sestria-content-private.pem" "$(git rev-parse --git-common-dir)/../build/content-signing/sestria-content-private.pem"; do
    [[ -f "$candidate" ]] && key="$candidate" && break
  done
fi
[[ -n "$key" && -f "$key" ]] || { echo 'Chiave di firma non trovata: imposta SESTRIA_CONTENT_KEY.' >&2; exit 1; }
cmp -s scripts/content_pack.gd mobile/scripts/content_pack.gd || { echo 'scripts/content_pack.gd e mobile/scripts/content_pack.gd devono essere identici.' >&2; exit 1; }
for info in content.json mobile/content.json; do
  python3 - "$info" "$version" <<'PY'
import json, sys
info = json.load(open(sys.argv[1]))
if info.get("content") != sys.argv[2]:
    sys.exit(f"{sys.argv[1]}: content={info.get('content')!r}, atteso {sys.argv[2]!r}")
PY
done
release="build/release"
mkdir -p "$release"
rm -f "$release"/Sestria-v"$version"-*-content.pck "$release/Sestria-v$version-content.json"
"$godot_bin" --headless --path . --import >/dev/null 2>&1 || true
(cd mobile && "$godot_bin" --headless --path . --import >/dev/null 2>&1 || true)
"$godot_bin" --headless --path . --export-pack "macOS" "$project_dir/$release/Sestria-v$version-macos-content.pck" >/dev/null 2>&1
"$godot_bin" --headless --path . --export-pack "Windows x64" "$project_dir/$release/Sestria-v$version-windows-content.pck" >/dev/null 2>&1
(cd mobile && "$godot_bin" --headless --path . --export-pack "Android Mobile Saga" "$project_dir/$release/Sestria-v$version-android-content.pck" >/dev/null 2>&1)
engine="$("$godot_bin" --version | awk -F. '{print $1"."$2}')"
body="$(python3 - "$version" "$engine" "$release" <<'PY'
import hashlib, json, os, sys
version, engine, release = sys.argv[1:4]
packs = {}
for key, info in (("macos", "content.json"), ("windows", "content.json"), ("android", "mobile/content.json")):
    name = f"Sestria-v{version}-{key}-content.pck"
    data = open(os.path.join(release, name), "rb").read()
    packs[key] = {"name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "min_base": json.load(open(info))["min_base"]}
print(json.dumps({"schema": 1, "version": version, "engine": engine, "packs": packs}, separators=(",", ":"), sort_keys=True), end="")
PY
)"
signature="$(printf '%s' "$body" | openssl dgst -sha256 -sign "$key" | base64 | tr -d '\n')"
printf '%s\n%s\n' "$body" "$signature" > "$release/Sestria-v$version-content.json"
# Controllo indipendente con il codice e la chiave pubblica che stanno nell'app.
"$godot_bin" --headless --path . --script res://tests/content_release_check.gd -- "$project_dir/$release" "$version" 2>&1 | grep -E "^(OK|RELEASE|ERROR)" 
echo "Allega alla release v$version: $release/Sestria-v$version-{macos,windows,android}-content.pck e $release/Sestria-v$version-content.json"
