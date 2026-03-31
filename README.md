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
| Commands | 61 | Slash commands (/plan, /tdd, /ship, /qa, /e2e, /rust-build, etc.) |
| Skills | 79 | Deep reference material (coding-standards, django-patterns, rust-testing, etc.) |
| Rules | 14 sets | Common + 13 language-specific rule sets (TypeScript, Python, Go, Rust, etc.) |
| Hooks | Full | Pre/PostToolUse, SessionStart/End, Stop, PreCompact lifecycle hooks |
| MCP Servers | 24 | GitHub, Supabase, Vercel, Railway, Cloudflare, Playwright, Context7, etc. |
| IDE Configs | 3 | Cursor, Codex, OpenCode cross-IDE support |

## Install Script Features

- Works on Linux, macOS, Windows (Git Bash / WSL)
- Backs up existing `~/.claude` config before overwriting
- Installs external skills (gstack) from their repos
- Installs Claude Code plugins (claude-mem, frontend-design, understand-anything, rust-analyzer-lsp)
- Sets executable permissions on scripts
- Prompts for API key configuration

## Post-Install: API Keys

After running `install.sh`, edit these files and replace `YOUR_*_HERE` placeholders:

1. `~/.claude/mcp-configs/mcp-servers.json` — GitHub PAT, Firecrawl, Exa, fal.ai, Browserbase, Confluence
2. `~/.claude/claude_code_config.json` — Notion API token

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
├── claude-config/          # All configuration files
│   ├── agents/             # 29 agent definitions
│   ├── commands/           # 61 slash commands
│   ├── skills/             # 79 skills
│   ├── rules/              # 14 rule sets
│   │   ├── common/         # Language-agnostic rules
│   │   ├── typescript/     # Language-specific overrides
│   │   └── ...
│   ├── scripts/            # Hook runtime scripts
│   ├── hooks/              # Hook configuration
│   ├── mcp-configs/        # MCP server definitions
│   ├── ecc/                # ECC install state
│   ├── settings.json       # Global settings
│   └── ...
└── README.md
```
