#!/usr/bin/env bash
# Verifica che OpenCode usi il provider applefm e completi un tool call.
# È più lento dello smoke test HTTP: il modello on-device impiega qualche secondo.
set -euo pipefail

MODEL="${1:-applefm/system}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$REPO_DIR"

log "Eseguo prompt con tool su $MODEL (può volerci un minuto)"
output="$(opencode run --auto --model "$MODEL" \
  "Usa il tool glob con pattern 'README.md' per verificare che il file esista, poi rispondi." 2>&1)" \
  || fail "opencode run è terminato con errore: $output"

printf '%s\n' "$output"

if grep -qiE 'unsupported pattern|Provided [0-9.]+ tokens|Nothing to compact|tool\.execution.*error|Model unavailable' <<<"$output"; then
  fail "errore noto nella risposta di OpenCode"
fi

# La prova è il tool call, non la forma della risposta finale: AFM ha 8K di
# contesto e può rigenerare i checkpoint di OpenCode prima di concludere.
if ! grep -q 'Glob' <<<"$output"; then
  fail "OpenCode non risulta aver eseguito il tool glob"
fi

log "SMOKE TEST OPENCODE PASS"
