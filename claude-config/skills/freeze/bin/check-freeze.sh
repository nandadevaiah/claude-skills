#!/usr/bin/env bash
# Freeze mode: block Edit/Write operations outside the allowed directory
# Reads tool input from stdin (JSON with "file_path" field)

set -euo pipefail

STATE_DIR="${HOME}/.claude/state"
FREEZE_FILE="$STATE_DIR/freeze-dir.txt"

# If no freeze boundary is set, allow everything
if [ ! -f "$FREEZE_FILE" ]; then
  exit 0
fi

FREEZE_DIR=$(cat "$FREEZE_FILE")

if [ -z "$FREEZE_DIR" ]; then
  exit 0
fi

# Read the tool input JSON from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Resolve to absolute path if relative
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# Check if the file path starts with the freeze directory
if [[ "$FILE_PATH" != "$FREEZE_DIR"* ]]; then
  cat <<EOF
{"permissionDecision": "deny", "message": "BLOCKED: Edit outside freeze boundary. File '$FILE_PATH' is not within '$FREEZE_DIR'. Run /unfreeze to remove the restriction."}
EOF
fi
