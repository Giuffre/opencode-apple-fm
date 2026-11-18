#!/usr/bin/env bash
# Verify that OpenCode uses the applefm provider and completes a tool call.
# Slower than the HTTP smoke test: the on-device model takes a few seconds.
set -euo pipefail

MODEL="${1:-applefm/system}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[0;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$REPO_DIR"

log "Running a tool prompt on $MODEL (this may take a minute)"
output="$(opencode run --auto --model "$MODEL" \
  "Use the glob tool with pattern 'README.md' to check that the file exists, then reply." 2>&1)" \
  || fail "opencode run exited with an error: $output"

printf '%s\n' "$output"

if grep -qiE 'unsupported pattern|Provided [0-9.]+ tokens|Nothing to compact|tool\.execution.*error|Model unavailable' <<<"$output"; then
  fail "known error in the OpenCode response"
fi

# The proof is the tool call, not the shape of the final reply: AFM has 8K of
# context and may regenerate OpenCode checkpoints before concluding.
if ! grep -q 'Glob' <<<"$output"; then
  fail "OpenCode does not appear to have executed the glob tool"
fi

log "SMOKE TEST OPENCODE PASS"
