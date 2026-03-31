# Electron PATH Enrichment for macOS Tool Discovery

**Extracted:** 2026-03-30
**Context:** Electron GUI apps spawning external CLI tools (npm, pip, brew, cargo)

## Problem
Electron apps on macOS don't inherit the user's shell PATH from `.zshrc`/`.bashrc`. Tools installed via Homebrew (`/opt/homebrew/bin`), nvm, pip (`~/.local/bin`), or cargo (`~/.cargo/bin`) are invisible to `execFile`, `which`, and spawned PTY sessions. Users see "command not found" for tools that work fine in their terminal.

## Solution
Build an enriched PATH by prepending common tool locations before any `execFile` or PTY spawn:

```typescript
function getEnrichedEnv(): Record<string, string | undefined> {
  const home = process.env.HOME || '';
  const extraPaths = [
    '/opt/homebrew/bin', '/opt/homebrew/sbin',  // macOS Apple Silicon
    '/usr/local/bin', '/usr/local/sbin',         // macOS Intel + standard
    path.join(home, '.local/bin'),               // pip install --user
    path.join(home, '.cargo/bin'),               // Rust/cargo
  ];

  // NVM: find latest node version
  const nvmDir = process.env.NVM_DIR || path.join(home, '.nvm');
  try {
    const versionsDir = path.join(nvmDir, 'versions', 'node');
    if (fs.existsSync(versionsDir)) {
      const versions = fs.readdirSync(versionsDir).sort().reverse();
      if (versions.length > 0) {
        extraPaths.unshift(path.join(versionsDir, versions[0], 'bin'));
      }
    }
  } catch { /* nvm not installed */ }

  return { ...process.env, PATH: [...extraPaths, process.env.PATH || ''].join(':') };
}

// Usage: execFile('which', ['claude'], { env: getEnrichedEnv() }, callback);
// Usage: pty.spawn(shell, args, { env: getEnrichedEnv() });
```

**Apply in ALL places** that run external commands:
- PTY session spawning (terminal creation)
- Agent install checking (`which <command>`)
- Version detection (`<command> --version`)
- Availability scanning (periodic PATH check)

## When to Use
- Any Electron app that spawns CLI tools
- Any Node.js GUI app on macOS
- Anywhere `execFile`, `spawn`, or `which` is used from a non-shell context
