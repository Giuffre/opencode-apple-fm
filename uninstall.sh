#!/usr/bin/env bash
# Remove the LaunchAgent and the applefm configuration from OpenCode.
set -euo pipefail

LABEL="ai.opencode.applefm"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/applefm-compat"

log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m ! \033[0m %s\n' "$*" >&2; }

uid="$(id -u)"
if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
  log "Stopping LaunchAgent"
  launchctl bootout "gui/$uid/$LABEL" || warn "bootout failed"
fi

if [[ -f "$PLIST" ]]; then
  log "Removing $PLIST"
  rm "$PLIST"
fi

if [[ -d "$PLUGIN_DIR" ]]; then
  log "Removing plugin $PLUGIN_DIR"
  rm -rf "$PLUGIN_DIR"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  log "Removing provider and agent from $CONFIG_FILE"
  python3 - "$CONFIG_FILE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    config = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    print(f"Cannot parse {path}: {exc}", file=sys.stderr)
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

# Remove only the setting that this installer added.
if config.get("compaction") == {"auto": False}:
    config.pop("compaction", None)

path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY
fi

log "Done. OpenCode reloads configuration automatically."
