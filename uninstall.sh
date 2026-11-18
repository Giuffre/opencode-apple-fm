#!/usr/bin/env bash
# Rimuove LaunchAgent e la configurazione applefm da OpenCode.
set -euo pipefail

LABEL="ai.opencode.applefm"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/applefm-compat"

log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m ! \033[0m %s\n' "$*" >&2; }

uid="$(id -u)"
if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
  log "Fermo LaunchAgent"
  launchctl bootout "gui/$uid/$LABEL" || warn "bootout non riuscito"
fi

if [[ -f "$PLIST" ]]; then
  log "Rimuovo $PLIST"
  rm "$PLIST"
fi

if [[ -d "$PLUGIN_DIR" ]]; then
  log "Rimuovo plugin $PLUGIN_DIR"
  rm -rf "$PLUGIN_DIR"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  log "Rimuovo provider e agente da $CONFIG_FILE"
  python3 - "$CONFIG_FILE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    config = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    print(f"Impossibile parsare {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

providers = config.get("providers")
if isinstance(providers, dict):
    providers.pop("applefm", None)
    if not providers:
        config.pop("providers", None)

agents = config.get("agents")
if isinstance(agents, dict):
    agents.pop("applefm", None)
    if not agents:
        config.pop("agents", None)

# Rimuove solo l'impostazione che abbiamo aggiunto noi.
if config.get("compaction") == {"auto": False}:
    config.pop("compaction", None)

path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY
fi

log "Fatto. OpenCode ricarica la configurazione automaticamente."
