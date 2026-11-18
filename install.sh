#!/usr/bin/env bash
# Installa un provider OpenCode collegato al Foundation Model on-device di macOS.
# Verificato su macOS 27.2.1 (26B131), OpenCode v2.3.0.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="ai.opencode.applefm"
PORT="${FM_PORT:-1976}"
TOOLS=true
COMPACTION_AUTO=false

usage() {
  cat <<EOF
Uso: ./install.sh [--port <porta>] [--no-tools] [--keep-compaction]

  --port <porta>       Porta loopback di fm serve (default: 1976, oppure \$FM_PORT)
  --no-tools           Disabilita tool calling nel provider (utile su macOS 27.0.x)
  --keep-compaction    Mantiene i checkpoint automatici di OpenCode (non consigliato
                       con un modello da 8K: generano loop di riepiloghi)
  -h, --help           Mostra questo aiuto
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      [[ $# -ge 2 ]] || { echo "Errore: --port richiede un valore" >&2; exit 2; }
      PORT="$2"
      shift 2
      ;;
    --no-tools)
      TOOLS=false
      shift
      ;;
    --keep-compaction)
      COMPACTION_AUTO=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opzione sconosciuta: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m ! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31mERRORE:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$PORT" =~ ^[0-9]+$ ]] || die "La porta deve essere un numero: $PORT"
(( PORT >= 1 && PORT <= 65535 )) || die "Porta fuori intervallo: $PORT"

for tool in python3 curl lsof; do
  command -v "$tool" >/dev/null 2>&1 || die "Strumento richiesto non trovato: $tool"
done

# ---------------------------------------------------------------- preflight
log "Verifica prerequisites"
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 27 ]] || die "Serve macOS 27 o successivo (trovato: $(sw_vers -productVersion))"

arch="$(uname -m)"
[[ "$arch" == "arm64" ]] || die "Serve Apple Silicon (trovato: $arch)"

[[ -x /usr/bin/fm ]] || die "/usr/bin/fm non presente"

license_status="$(fm license --status 2>&1 || true)"
grep -qi 'agreed' <<<"$license_status" \
  || die "Licenza fm non accettata. Esegui: sudo fm license"

models_output="$(fm models 2>&1 || true)"
grep -q '✓ system' <<<"$models_output" \
  || die "Modello 'system' non disponibile. Attiva Apple Intelligence e scarica il modello."

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN | awk 'NR > 1 {print $1}' | grep -qx 'fm'; then
    warn "Porta $PORT già usata da fm serve: reinstallazione su servizio esistente."
  else
    die "La porta $PORT è già occupata. Chiudi il processo o usa FM_PORT=<altra-porta>."
  fi
fi

# ------------------------------------------------------------------ install
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CONFIG_FILE="$CONFIG_DIR/opencode.jsonc"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-apple-fm"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_DIR/$LABEL.plist"

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LAUNCH_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
  backup="$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_FILE" "$backup"
  log "Backup configurazione: $backup"
fi

log "Aggiorno $CONFIG_FILE"
python3 - "$CONFIG_FILE" "$TOOLS" "$PORT" "$COMPACTION_AUTO" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
tools = sys.argv[2] == "true"
port = sys.argv[3]
compaction_auto = sys.argv[4] == "true"

if path.exists():
    try:
        config = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        print(
            f"Impossibile parsare {path} come JSON: {exc}\n"
            "Converti il file in JSON puro (senza commenti) e riprova.",
            file=sys.stderr,
        )
        raise SystemExit(1)
else:
    config = {}

config.setdefault("$schema", "https://opencode.ai/config.json")

# Con 8192 token i checkpoint automatici generano riepiloghi che il modello
# rilegge come istruzioni, entrando in loop. Si possono riattivare col flag.
config.setdefault("compaction", {})["auto"] = compaction_auto

# Rimuove il vecchio provider V1 `fm` se presente, lasciando gli altri intatti.
legacy = config.get("provider")
if isinstance(legacy, dict) and "fm" in legacy:
    del legacy["fm"]
    if not legacy:
        config.pop("provider", None)

providers = config.setdefault("providers", {})
providers["applefm"] = {
    "name": "Apple Foundation Model (on-device)",
    "package": "@opencode/ai/providers/openai-compatible",
    "settings": {
        "baseURL": f"http://127.0.0.1:{port}/v1",
        "apiKey": "unused",
    },
    "models": {
        "system": {
            "name": "AFM 3 Core Advanced (on-device)",
            "modelID": "system",
            "capabilities": {
                "tools": tools,
                "input": ["text", "image"],
                "output": ["text"],
            },
            "limit": {"context": 8192, "output": 4096},
        }
    },
}

agents = config.setdefault("agents", {})
agents["applefm"] = {
    "description": "Apple on-device Foundation Model: veloce, privato, contesto 8K",
    "mode": "primary",
    "model": "applefm/system",
}

path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY

# OpenCode carica automaticamente i plugin dalla directory di configurazione.
PLUGIN_DIR="$CONFIG_DIR/plugins/applefm-compat"
mkdir -p "$PLUGIN_DIR"
if [[ -f "$PLUGIN_DIR/index.ts" ]]; then
  backup="$PLUGIN_DIR/index.ts.bak.$(date +%Y%m%d%H%M%S)"
  cp "$PLUGIN_DIR/index.ts" "$backup"
  log "Backup plugin precedente: $backup"
fi
cp "$REPO_DIR/plugins/applefm-compat/index.ts" "$PLUGIN_DIR/index.ts"
log "Plugin installato: $PLUGIN_DIR/index.ts"

log "Installo LaunchAgent $LABEL"
sed \
  -e "s|__PORT__|$PORT|g" \
  -e "s|__HOME__|$HOME|g" \
  -e "s|__DATA_DIR__|$DATA_DIR|g" \
  "$REPO_DIR/launchd/ai.opencode.applefm.plist.template" > "$PLIST"

uid="$(id -u)"
launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$PLIST"
launchctl kickstart -k "gui/$uid/$LABEL"

log "Attendo /health su 127.0.0.1:$PORT"
base="http://127.0.0.1:$PORT"
ready=false
for _ in $(seq 1 30); do
  if curl -fsS "$base/health" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || die "fm serve non risponde. Controlla: $DATA_DIR/fm-serve.err.log"

log "Smoke test (tool calling)"
if python3 "$REPO_DIR/scripts/smoke-test.py" "$PORT"; then
  log "Tool calling verificato"
else
  warn "Tool calling NON verificato. Se sei su macOS 27.0.x, aggiorna oppure reinstalla con --no-tools."
fi

cat <<EOF

$(log "Installazione completata")

  Provider : applefm/system
  Endpoint : $base/v1
  Config   : $CONFIG_FILE
  Plugin   : $PLUGIN_DIR/index.ts
  Servizio : $LABEL (loopback, nessuna autenticazione)
  Log      : $DATA_DIR/

Prova subito:

  opencode run --model applefm/system "Rispondi solo con: OK"

Test con tool (--auto approva i permessi in modalità non interattiva):

  opencode run --auto --model applefm/system "Usa il tool glob con pattern 'README.md' per verificare che il file esista"

Oppure dentro OpenCode:

  /models        -> seleziona applefm/system
  /agent         -> seleziona applefm (facoltativo)

La configurazione viene ricaricata automaticamente da OpenCode.
EOF
