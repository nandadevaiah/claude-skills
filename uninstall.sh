#!/usr/bin/env bash
# Restore Claude Code config from the most recent backup
set -euo pipefail

TARGET_DIR="$HOME/.claude"
BACKUP_ROOT="$TARGET_DIR/backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Find most recent backup
LATEST_BACKUP=$(find "$BACKUP_ROOT" -maxdepth 1 -name "pre-install-*" -type d 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    error "No backup found in $BACKUP_ROOT"
    exit 1
fi

info "Found backup: $LATEST_BACKUP"
read -rp "Restore from this backup? This will overwrite current config. (y/N) " yn
[[ "$yn" =~ ^[Yy]$ ]] || exit 0

for item in "$LATEST_BACKUP"/*; do
    name=$(basename "$item")
    rm -rf "$TARGET_DIR/$name"
    cp -r "$item" "$TARGET_DIR/$name"
    ok "Restored $name"
done

ok "Config restored from $LATEST_BACKUP"
