#!/usr/bin/env bash
# Careful mode: check bash commands for destructive patterns
# Reads tool input from stdin (JSON with "command" field)

set -euo pipefail

# Read the tool input JSON from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.command // empty' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Safe exceptions - common build cleanup commands
SAFE_PATTERNS=(
  "rm -rf node_modules"
  "rm -rf .next"
  "rm -rf dist"
  "rm -rf __pycache__"
  "rm -rf .cache"
  "rm -rf build"
  "rm -rf .turbo"
  "rm -rf coverage"
  "rm -rf target"
  "rm -rf .gradle"
  "rm -rf .pytest_cache"
  "rm -rf .mypy_cache"
  "rm -rf .ruff_cache"
  "rm -rf tmp/"
  "rm -rf .tmp"
)

for safe in "${SAFE_PATTERNS[@]}"; do
  if [[ "$COMMAND" == *"$safe"* ]]; then
    exit 0
  fi
done

# Destructive patterns to check
WARN=""

# File deletion
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)'; then
  WARN="DESTRUCTIVE: Recursive file deletion detected (rm -r). This permanently removes files and directories."
fi

# Database destruction
if echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)'; then
  WARN="DESTRUCTIVE: SQL DROP detected. This permanently removes database objects."
fi

if echo "$COMMAND" | grep -qiE 'TRUNCATE\s'; then
  WARN="DESTRUCTIVE: SQL TRUNCATE detected. This permanently removes all rows from a table."
fi

# Git destruction
if echo "$COMMAND" | grep -qE 'git\s+push\s+(-[a-zA-Z]*f|--force)'; then
  WARN="DESTRUCTIVE: Force push detected. This rewrites remote history and can cause data loss for collaborators."
fi

if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  WARN="DESTRUCTIVE: git reset --hard detected. This discards all uncommitted changes permanently."
fi

if echo "$COMMAND" | grep -qE 'git\s+(checkout|restore)\s+\.$'; then
  WARN="DESTRUCTIVE: git checkout/restore . detected. This discards all uncommitted changes."
fi

if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  WARN="DESTRUCTIVE: git clean -f detected. This permanently removes untracked files."
fi

# Kubernetes destruction
if echo "$COMMAND" | grep -qE 'kubectl\s+delete'; then
  WARN="DESTRUCTIVE: kubectl delete detected. This removes Kubernetes resources from the cluster."
fi

# Docker destruction
if echo "$COMMAND" | grep -qE 'docker\s+(rm\s+-f|system\s+prune|volume\s+prune|image\s+prune)'; then
  WARN="DESTRUCTIVE: Docker cleanup detected. This removes containers, images, or volumes."
fi

# Terraform destruction
if echo "$COMMAND" | grep -qE 'terraform\s+destroy'; then
  WARN="DESTRUCTIVE: terraform destroy detected. This tears down infrastructure."
fi

# Helm destruction
if echo "$COMMAND" | grep -qE 'helm\s+(uninstall|delete)'; then
  WARN="DESTRUCTIVE: helm uninstall detected. This removes a deployed release."
fi

if [ -n "$WARN" ]; then
  # Return ask decision so user gets prompted
  cat <<EOF
{"permissionDecision": "ask", "message": "$WARN Proceed with caution."}
EOF
fi
