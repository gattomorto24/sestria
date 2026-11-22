#!/usr/bin/env bash
# Avvia il finto Google e lancia il collaudo del salvataggio su Drive. Uso: tools/run_drive_test.sh /percorso/godot
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
python3 tools/fake_google.py 32660 >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
sleep 1
HOME_DIR="$(mktemp -d)"
HOME="$HOME_DIR" SESTRIA_DRIVE_TEST=http://127.0.0.1:32660 "$GODOT" --headless --path . -s tests/drive_test.gd
