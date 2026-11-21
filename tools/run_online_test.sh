#!/usr/bin/env bash
# Avvia il tracker di prova locale, esegue il collaudo online e lo ferma.
# Uso: tools/run_online_test.sh [percorso del binario Godot]
set -u
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
python3 tools/mock_tracker.py 32650 >/dev/null 2>&1 &
TRACKER=$!
trap 'kill $TRACKER 2>/dev/null' EXIT
sleep 1
"$GODOT" --headless --path . -s tests/online_test.gd || exit 1
"$GODOT" --headless --fixed-fps 120 --path . -s tests/online_match_test.gd -- --lan-favors
