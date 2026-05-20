#!/usr/bin/env bash
# Claude Skills Installer
# Installs Claude Code configuration (agents, skills, commands, rules, hooks, MCP configs)
# Works on Linux, macOS, and Windows (Git Bash / WSL)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/claude-config"
TARGET_DIR="$HOME/.claude"
BACKUP_DIR="$TARGET_DIR/backups/pre-install-$(date +%Y%m%d-%H%M%S)"

# Colors (safe for non-color terminals)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Preflight checks ────────────────────────────────────────────────────────

if [[ ! -d "$SOURCE_DIR" ]]; then
    error "Source directory not found: $SOURCE_DIR"
    error "Run this script from the repo root."
    exit 1
fi

if ! command -v claude &>/dev/null; then
    warn "Claude Code CLI not found. Install it first:"
    echo "  npm install -g @anthropic-ai/claude-code"
    echo ""
    read -rp "Continue anyway? (y/N) " yn
    [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

# ─── Detect platform ─────────────────────────────────────────────────────────

PLATFORM="unknown"
case "$(uname -s)" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="macos" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
esac
info "Platform: $PLATFORM"

# ─── Backup existing config ──────────────────────────────────────────────────

if [[ -d "$TARGET_DIR" ]]; then
    info "Backing up existing config to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    # Back up only the dirs we're about to overwrite
    for dir in agents commands rules scripts skills hooks mcp-configs ecc; do
        if [[ -d "$TARGET_DIR/$dir" ]]; then
            cp -r "$TARGET_DIR/$dir" "$BACKUP_DIR/$dir"
        fi
    done
    for file in settings.json claude_code_config.json plugin.json AGENTS.md README.md; do
        if [[ -f "$TARGET_DIR/$file" ]]; then
            cp "$TARGET_DIR/$file" "$BACKUP_DIR/$file"
        fi
    done
    ok "Backup complete"
else
    info "No existing ~/.claude directory. Fresh install."
    mkdir -p "$TARGET_DIR"
fi

# ─── Install ─────────────────────────────────────────────────────────────────

info "Installing Claude Code configuration..."

# Install order matters for skills/:
#   1. Clone gstack first (provides /checkpoint, /codex, /cso, /design-*, etc.)
#   2. Copy ECC skills per-entry (overrides any gstack-created symlinks with
#      our clean de-telemetry'd forks of autoplan/ship/qa/freeze/guard/etc.)
# This guarantees ECC forks always win, even if gstack's own setup is re-run
# later (just re-run install.sh to restore).

# ─── Install external skills (gstack) ────────────────────────────────────────
# Done FIRST so the ECC skills copy below can overwrite any symlinks gstack
# creates for skill names we also fork (autoplan, ship, qa, freeze, etc.)

GSTACK_DIR="$TARGET_DIR/skills/gstack"
mkdir -p "$TARGET_DIR/skills"
if [[ ! -d "$GSTACK_DIR" ]]; then
    info "Installing gstack skill from garrytan/gstack..."
    if command -v git &>/dev/null; then
        git clone --depth 1 https://github.com/garrytan/gstack "$GSTACK_DIR" 2>/dev/null && \
            ok "Installed gstack skill" || \
            warn "Failed to clone gstack (may be private repo). Skipping."
    else
        warn "git not found. Skipping gstack install."
    fi
else
    ok "gstack skill already installed"
fi

# Copy non-skills config directories (full rm -rf + copy)
for dir in agents commands rules scripts hooks mcp-configs ecc; do
    if [[ -d "$SOURCE_DIR/$dir" ]]; then
        rm -rf "$TARGET_DIR/$dir"
        cp -r "$SOURCE_DIR/$dir" "$TARGET_DIR/$dir"
        ok "Installed $dir/"
    fi
done

# Copy skills per-entry so we preserve the gstack/ clone and forcibly
# overwrite any gstack-created symlinks with our real ECC fork files.
if [[ -d "$SOURCE_DIR/skills" ]]; then
    skill_count=0
    for skill_src in "$SOURCE_DIR/skills"/*/; do
        name=$(basename "$skill_src")
        # Never touch the gstack clone subdir
        [[ "$name" == "gstack" ]] && continue
        rm -rf "$TARGET_DIR/skills/$name"
        cp -r "$skill_src" "$TARGET_DIR/skills/$name"
        skill_count=$((skill_count+1))
    done
    ok "Installed skills/ ($skill_count ECC skills, gstack preserved)"
fi

# Copy top-level config files
for file in settings.json claude_code_config.json plugin.json AGENTS.md README.md; do
    if [[ -f "$SOURCE_DIR/$file" ]]; then
        cp "$SOURCE_DIR/$file" "$TARGET_DIR/$file"
        ok "Installed $file"
    fi
done

# Copy IDE-specific configs (.agents, .codex, .cursor, .opencode)
for dotdir in .agents .codex .cursor .opencode; do
    if [[ -d "$SOURCE_DIR/$dotdir" ]]; then
        rm -rf "$TARGET_DIR/$dotdir"
        cp -r "$SOURCE_DIR/$dotdir" "$TARGET_DIR/$dotdir"
        ok "Installed $dotdir/"
    fi
done

# ─── Install plugins ─────────────────────────────────────────────────────────

info ""
info "Installing Claude Code plugins..."

PLUGINS=(
    "rust-analyzer-lsp@claude-plugins-official"
    "claude-mem@thedotmack"
    "frontend-design@claude-plugins-official"
    "understand-anything@understand-anything"
)

for plugin in "${PLUGINS[@]}"; do
    if command -v claude &>/dev/null; then
        info "Installing plugin: $plugin"
        claude plugin install "$plugin" 2>/dev/null && \
            ok "Installed $plugin" || \
            warn "Failed to install $plugin (install manually later)"
    else
        warn "Claude CLI not available. Install plugin manually: claude plugin install $plugin"
    fi
done

# ─── Fix permissions ─────────────────────────────────────────────────────────

if [[ "$PLATFORM" != "windows" ]]; then
    find "$TARGET_DIR/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$TARGET_DIR/skills" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    ok "Set executable permissions on scripts"
fi

# ─── Post-install: MCP server secrets ─────────────────────────────────────────

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "  SETUP REQUIRED: Configure your API keys"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "Edit these files and replace YOUR_*_HERE placeholders:"
echo ""
echo "  1. ~/.claude/mcp-configs/mcp-servers.json"
echo "     - GITHUB_PERSONAL_ACCESS_TOKEN"
echo "     - FIRECRAWL_API_KEY"
echo "     - EXA_API_KEY"
echo "     - FAL_KEY"
echo "     - BROWSERBASE_API_KEY"
echo "     - CONFLUENCE_* credentials"
echo ""
echo "  2. ~/.claude/claude_code_config.json"
echo "     - Notion API token"
echo ""
echo "  3. Google Cloud MCP servers (gcloud, gcloud-observability,"
echo "     gcloud-storage, gcloud-backupdr) — no API keys, but require:"
echo "     - gcloud CLI installed: https://cloud.google.com/sdk/docs/install"
echo "     - Auth: gcloud auth login && gcloud auth application-default login"
echo "     - Default project: gcloud config set project YOUR_PROJECT_ID"
echo ""
echo "  4. Supabase MCP (supabase) — hosted HTTP server with OAuth"
echo "     - Replace YOUR_PROJECT_REF in the URL with your project ID, or"
echo "       remove ?project_ref=... for account-wide access"
echo "     - Run /mcp in Claude Code to complete OAuth login"
echo ""
echo "  5. Stripe MCP (stripe) — hosted HTTP server with OAuth"
echo "     - Run /mcp in Claude Code to complete OAuth login, OR add a"
echo "       Bearer header with a restricted API key (docs.stripe.com/mcp)"
echo ""

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "  Installation complete!"
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Installed:"
echo "    - 29 agents"
echo "    - 64 slash commands"
echo "    - 82 skills"
echo "    - 14 rule sets (common + 13 languages)"
echo "    - Hook system (pre/post tool use, session lifecycle)"
echo "    - MCP server configs (29 servers, incl. 4 Google Cloud, Supabase, Stripe)"
echo "    - IDE configs (Cursor, Codex, OpenCode)"
echo ""
echo "  Backup location: $BACKUP_DIR"
echo ""
echo "  Next steps:"
echo "    1. Configure API keys (see above)"
echo "    2. Start Claude Code: claude"
echo ""
