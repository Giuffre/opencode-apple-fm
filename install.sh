#!/usr/bin/env bash
# Install an OpenCode provider backed by the macOS on-device Foundation Model.
# Verified on macOS 27.2.1 (26B131), OpenCode v2.3.0.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="ai.opencode.applefm"
PORT="${FM_PORT:-1976}"
TOOLS=true
COMPACTION_AUTO=false

usage() {
  cat <<EOF
Usage: ./install.sh [--port <port>] [--no-tools] [--keep-compaction]

  --port <port>        Loopback port for fm serve (default: 1976, or \$FM_PORT)
  --no-tools           Disable tool calling in the provider (useful on macOS 27.0.x)
  --keep-compaction    Keep OpenCode's automatic checkpoints (not recommended
                       with an 8K model: they cause summary loops)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      [[ $# -ge 2 ]] || { echo "Error: --port requires a value" >&2; exit 2; }
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
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m ! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be a number: $PORT"
(( PORT >= 1 && PORT <= 65535 )) || die "Port out of range: $PORT"

for tool in python3 curl lsof; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool not found: $tool"
done

# ---------------------------------------------------------------- preflight
log "Checking prerequisites"
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 27 ]] || die "macOS 27 or later required (found: $(sw_vers -productVersion))"

arch="$(uname -m)"
[[ "$arch" == "arm64" ]] || die "Apple Silicon required (found: $arch)"

[[ -x /usr/bin/fm ]] || die "/usr/bin/fm not found"

license_status="$(fm license --status 2>&1 || true)"
grep -qi 'agreed' <<<"$license_status" \
  || die "fm license not accepted. Run: sudo fm license"

models_output="$(fm models 2>&1 || true)"
grep -q '✓ system' <<<"$models_output" \
  || die "Model 'system' is unavailable. Enable Apple Intelligence and download the model."

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN | awk 'NR > 1 {print $1}' | grep -qx 'fm'; then
    warn "Port $PORT is already used by fm serve: reinstalling over the existing service."
  else
    die "Port $PORT is already in use. Stop the process or use FM_PORT=<other-port>."
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
  log "Configuration backup: $backup"
fi

log "Updating $CONFIG_FILE"
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
            f"Cannot parse {path} as JSON: {exc}\n"
            "Convert the file to plain JSON (no comments) and retry.",
            file=sys.stderr,
        )
        raise SystemExit(1)
else:
    config = {}

config.setdefault("$schema", "https://opencode.ai/config.json")

# With 8192 tokens, automatic checkpoints produce summaries that the model
# rereads as instructions and loops on. The flag can re-enable them.
config.setdefault("compaction", {})["auto"] = compaction_auto

# Remove the legacy V1 `fm` provider if present, leaving other entries intact.
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
    "description": "Apple on-device Foundation Model: fast, private, 8K context",
    "mode": "primary",
    "model": "applefm/system",
}

path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY

# OpenCode automatically loads plugins from its configuration directory.
PLUGIN_DIR="$CONFIG_DIR/plugins/applefm-compat"
mkdir -p "$PLUGIN_DIR"
if [[ -f "$PLUGIN_DIR/index.ts" ]]; then
  backup="$PLUGIN_DIR/index.ts.bak.$(date +%Y%m%d%H%M%S)"
  cp "$PLUGIN_DIR/index.ts" "$backup"
  log "Previous plugin backup: $backup"
fi
cp "$REPO_DIR/plugins/applefm-compat/index.ts" "$PLUGIN_DIR/index.ts"
log "Plugin installed: $PLUGIN_DIR/index.ts"

log "Installing LaunchAgent $LABEL"
sed \
  -e "s|__PORT__|$PORT|g" \
  -e "s|__HOME__|$HOME|g" \
  -e "s|__DATA_DIR__|$DATA_DIR|g" \
  "$REPO_DIR/launchd/ai.opencode.applefm.plist.template" > "$PLIST"

uid="$(id -u)"
launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$PLIST"
launchctl kickstart -k "gui/$uid/$LABEL"

log "Waiting for /health on 127.0.0.1:$PORT"
base="http://127.0.0.1:$PORT"
ready=false
for _ in $(seq 1 30); do
  if curl -fsS "$base/health" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || die "fm serve is not responding. Check: $DATA_DIR/fm-serve.err.log"

log "Smoke test (tool calling)"
if python3 "$REPO_DIR/scripts/smoke-test.py" "$PORT"; then
  log "Tool calling verified"
else
  warn "Tool calling NOT verified. On macOS 27.0.x, upgrade or reinstall with --no-tools."
fi

cat <<EOF

$(log "Installation complete")

  Provider : applefm/system
  Endpoint : $base/v1
  Config   : $CONFIG_FILE
  Plugin   : $PLUGIN_DIR/index.ts
  Service  : $LABEL (loopback, no authentication)
  Logs     : $DATA_DIR/

Try it now:

  opencode run --model applefm/system "Answer with only: OK"

Tool test (--auto approves permissions in non-interactive mode):

  opencode run --auto --model applefm/system "Use the glob tool with pattern 'README.md' to check that the file exists"

Or inside OpenCode:

  /models        -> select applefm/system
  /agent         -> select applefm (optional)

OpenCode reloads configuration automatically.
EOF
