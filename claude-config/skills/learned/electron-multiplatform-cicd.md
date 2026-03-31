# Electron Multi-Platform CI/CD with GitHub Actions

**Extracted:** 2026-03-30
**Context:** Building and releasing Electron apps for Linux, macOS, and Windows via GitHub Actions

## Problem
Electron apps with native dependencies (node-pty, node-gyp) fail to build on GitHub Actions runners due to:
1. Python 3.12+ removed `distutils` — node-gyp breaks with `ModuleNotFoundError: No module named 'distutils'`
2. macOS `hardenedRuntime` requires Apple Developer certificate — unsigned apps show "damaged" on macOS
3. Windows `signtool.exe` hangs when no signing certificate is configured
4. Windows NSIS downloads time out on slow GitHub runners

## Solution

### Workflow structure
```yaml
jobs:
  test:           # Run once on ubuntu
  build-linux:    # needs: test
  build-macos:    # needs: test (parallel with linux/windows)
  build-windows:  # needs: test
  release:        # needs: all builds, only on tags
```

### macOS fixes
```yaml
build-macos:
  runs-on: macos-latest
  steps:
    - run: python3 -m pip install setuptools --break-system-packages  # Fix distutils
    - run: npm ci
    - run: npx electron-builder --mac
```

In `electron-builder.yml` — do NOT use `hardenedRuntime: true` without a signing cert:
```yaml
mac:
  target: [dmg, zip]
  # hardenedRuntime: true  # REQUIRES Apple Developer cert ($99/yr)
```

Tell users: `xattr -cr /Applications/YourApp.app`

### Windows fixes
```yaml
build-windows:
  runs-on: windows-latest
  steps:
    - run: python3 -m pip install setuptools  # Fix distutils
    - run: npm ci
    - run: npx electron-builder --win
      env:
        ELECTRON_BUILDER_HTTP_TIMEOUT: 300000  # 5min timeout for NSIS download
      timeout-minutes: 20
```

In `electron-builder.yml` — disable signing without cert:
```yaml
win:
  target: [nsis, portable]
  signAndEditExecutable: false  # Prevents signtool.exe hang
```

### Release job
```yaml
release:
  needs: [build-linux, build-macos, build-windows]
  if: startsWith(github.ref, 'refs/tags/v')
  steps:
    - uses: actions/download-artifact@v4
    - uses: softprops/action-gh-release@v2
      with:
        files: artifacts/**/*
```

## When to Use
- Any Electron app with native Node.js modules (node-pty, better-sqlite3, etc.)
- Cross-platform desktop app distribution
- GitHub Actions CI/CD for desktop apps
- Projects without code signing certificates (open source, early stage)
