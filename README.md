# Claude Skills

Personal Claude Code configuration — agents, skills, commands, rules, hooks, and MCP server configs. Based on [Everything Claude Code (ECC)](https://github.com/affaan-m/everything-claude-code) v1.9.0, frozen and customized.

## Quick Start

```bash
git clone git@github.com:YOUR_USERNAME/claude-skills.git
cd claude-skills
./install.sh
```

## What's Included

| Component | Count | Description |
|-----------|-------|-------------|
| Agents | 29 | Specialized subagents (planner, architect, tdd-guide, code-reviewer, security-reviewer, etc.) |
| Commands | 63 | Slash commands (/plan, /tdd, /ship, /qa, /e2e, /flowlyte, /incident-report, etc.) |
| Skills | 81 | Deep reference material (coding-standards, flowlyte, incident-report, rust-testing, etc.) |
| Rules | 14 sets | Common + 13 language-specific rule sets (TypeScript, Python, Go, Rust, etc.) |
| Hooks | Full | Pre/PostToolUse, SessionStart/End, Stop, PreCompact lifecycle hooks |
| MCP Servers | 29 | GitHub, Supabase, Stripe, Vercel, Railway, Cloudflare, Playwright, Context7, Google Cloud (gcloud/observability/storage/backupdr), etc. |
| IDE Configs | 3 | Cursor, Codex, OpenCode cross-IDE support |

## Install Script Features

- Works on Linux, macOS, Windows (Git Bash / WSL)
- Backs up existing `~/.claude` config before overwriting
- Merges `~/.claude/CLAUDE.md` instead of overwriting it (see below)
- Installs external skills (gstack) from their repos
- Installs Claude Code plugins (claude-mem, frontend-design, understand-anything, rust-analyzer-lsp)
- Sets executable permissions on scripts
- Prompts for API key configuration

## CLAUDE.md: Managed Block

`~/.claude/CLAUDE.md` holds your global instructions, and it is the one file the
installer does not replace wholesale. It ships shared rules inside a pair of
marker lines:

```markdown
<!-- BEGIN managed: claude-skills -->
...shared rules from this repo...
<!-- END managed: claude-skills -->
```

On install, `lib/install-claude-md.sh` replaces only what is between those
markers. Anything above or below them is yours and is never touched — put
machine-specific preferences there. If the file does not exist yet it is copied
in whole (nothing to back up in that case); if it exists without markers the
block is appended to the end. Whenever an existing file is about to change, the
previous version is copied to the backup directory first.

A few things it deliberately handles rather than plough through:

- **Symlinked `CLAUDE.md`** (pointing into a dotfiles repo) — the link chain is
  resolved and the real file is rewritten, so the link survives.
- **CRLF files** (Git Bash / Windows) — markers still match, and the block is
  written back with the line endings the file already uses.
- **Damaged markers** — more than one of either marker, END before BEGIN, or
  BEGIN with no END. The installer refuses to guess: it leaves your file alone
  and writes the new version to `~/.claude/CLAUDE.md.new` for you to merge by
  hand. If a `.new` file is already there and differs from the repo version, it
  is left alone too, on the assumption you are mid-merge.

  An unindented marker line inside a fenced code block counts toward those
  totals like any other line, so a fence documenting this feature will trip the
  refusal *if the file also has a real block*. A fenced pair that is the only
  pair in the file is indistinguishable from a real one and gets treated as the
  managed block — indent marker lines by four spaces if you want to quote them
  safely.
- **A broken symlink** at `~/.claude/CLAUDE.md` — nothing is written; fix or
  remove the link and re-run.

Tests for all of this live in `tests/test-install-claude-md.sh`.

## Post-Install: API Keys

After running `install.sh`, edit these files and replace `YOUR_*_HERE` placeholders:

1. `~/.claude/mcp-configs/mcp-servers.json` — GitHub PAT, Firecrawl, Exa, fal.ai, Browserbase, Confluence
2. `~/.claude/claude_code_config.json` — Notion API token
3. Google Cloud MCP servers (`gcloud`, `gcloud-observability`, `gcloud-storage`, `gcloud-backupdr`) — no API keys, but require the [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```
4. `supabase` — hosted HTTP server ([supabase-community/supabase-mcp](https://github.com/supabase-community/supabase-mcp)) with OAuth. Replace `YOUR_PROJECT_REF` in the URL with your project ID (or remove the `project_ref` param for account-wide access), then run `/mcp` in Claude Code to complete login.
5. `stripe` — hosted HTTP server with OAuth ([docs.stripe.com/mcp](https://docs.stripe.com/mcp)). Run `/mcp` in Claude Code to authenticate, or add a Bearer header with a [restricted API key](https://docs.stripe.com/keys#create-restricted-api-key).

## Updating

Pull latest and re-run:

```bash
cd claude-skills
git pull
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

Restores from the most recent backup created by the installer.

## Structure

```
claude-skills/
├── install.sh              # Cross-platform installer
├── uninstall.sh            # Restore from backup
├── lib/
│   └── install-claude-md.sh  # Managed-block merge for CLAUDE.md
├── tests/
│   └── test-install-claude-md.sh  # Suite for the merge logic
├── claude-config/          # All configuration files
│   ├── agents/             # 29 agent definitions
│   ├── commands/           # 63 slash commands
│   ├── skills/             # 81 skills
│   ├── rules/              # 14 rule sets
│   │   ├── common/         # Language-agnostic rules
│   │   ├── typescript/     # Language-specific overrides
│   │   └── ...
│   ├── scripts/            # Hook runtime scripts
│   ├── hooks/              # Hook configuration
│   ├── mcp-configs/        # MCP server definitions
│   ├── ecc/                # ECC install state
│   ├── CLAUDE.md           # Global instructions (managed block only)
│   ├── settings.json       # Global settings
│   └── ...
└── README.md
```
