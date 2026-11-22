#!/bin/bash
# Esporta l'edizione web di Sestria in build/web e, con --publish, la pubblica sul branch gh-pages
# (GitHub Pages: https://gattomorto24.github.io/sestria/). Non usa GitHub Actions.
# Uso:  tools/export_web.sh 4.6            solo esportazione in build/web
#       tools/export_web.sh 4.6 --publish  esporta e pubblica
# La versione deve coincidere con config/version di project.godot (si aggiorna insieme a tutte le altre).
# gh-pages contiene sempre e soltanto l'ultima build web: un unico commit orfano, sovrascritto a ogni release.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Indica la versione, ad esempio 4.6}"
publish="${2:-}"
godot_bin="${SESTRIA_GODOT:-${SESTRIA_ANDROID_TOOLS:-/tmp/sestria-android-tools}/godot}"
templates_src="${SESTRIA_WEB_TEMPLATES:-$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable}"
templates_dst="$(dirname "$godot_bin")/editor_data/export_templates/4.7.1.stable"
repo="https://github.com/gattomorto24/sestria.git"
out="build/web"

configured="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
[ "$configured" = "$version" ] || { echo "project.godot dichiara la versione $configured, non $version: aggiornala prima (docs/releases.md)." >&2; exit 1; }

# Template web single-thread (niente SharedArrayBuffer: Pages non può inviare gli header COOP/COEP).
if [ ! -f "$templates_dst/web_nothreads_release.zip" ]; then
  [ -f "$templates_src/web_nothreads_release.zip" ] || { echo "Mancano i template web 4.7.1 (web_nothreads_release.zip) in $templates_src." >&2; exit 1; }
  mkdir -p "$templates_dst"
  cp "$templates_src"/web_nothreads_*.zip "$templates_dst/"
fi

rm -rf "$out"; mkdir -p "$out"
touch build/.gdignore   # Godot non deve importare le immagini generate in build/
"$godot_bin" --headless --path . --import >/dev/null 2>&1 || true
"$godot_bin" --headless --path . --export-release "Web" >/dev/null 2>&1

# Solo questi file vanno online. Tutto il resto (anche eventuali .import) viene scartato.
keep=(index.html index.js index.pck index.wasm index.png index.icon.png index.apple-touch-icon.png index.audio.worklet.js index.audio.position.worklet.js)
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
for f in "${keep[@]}"; do
  [ -f "$out/$f" ] || { echo "Esportazione incompleta: manca $out/$f" >&2; exit 1; }
  cp "$out/$f" "$stage/$f"
done
cp tools/web/privacy.html "$stage/privacy.html"
touch "$stage/.nojekyll"
printf '{"version":"%s","built":"%s"}\n' "$version" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$stage/version.json"
if find "$stage" \( -name "*.keystore" -o -name "*.jks" -o -name "*.pem" -o -name "*.p12" -o -name ".env*" -o -name "*.apk" -o -name "*.cfg" \) | grep -q .; then
  echo "File sensibile nella build web: pubblicazione annullata." >&2; exit 1
fi
rm -rf "$out"; mkdir -p "$out"; cp -R "$stage"/. "$out"/
echo "Build web $version in $out: $(du -sh "$out" | cut -f1)"
ls -l "$out" | awk 'NR>1{print "  "$5"\t"$9}'

[ "$publish" = "--publish" ] || { echo "Per pubblicare: tools/export_web.sh $version --publish"; exit 0; }

# Pubblicazione: commit orfano con la sola build, forzato su gh-pages.
pub="$(mktemp -d)"
trap 'rm -rf "$stage" "$pub"' EXIT
cp -R "$out"/. "$pub"/
(
  cd "$pub"
  git init -q -b gh-pages
  git add -A
  git -c user.name="gattomorto24" -c user.email="gattomorto24@users.noreply.github.com" commit -q -m "Sestria $version · edizione web"
  git push -q --force "$repo" gh-pages
)
echo "Pubblicato su gh-pages: https://gattomorto24.github.io/sestria/"
