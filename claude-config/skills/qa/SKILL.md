---
name: qa
version: 1.0.0
description: |
  Systematically QA test a web application and fix bugs found. Uses Playwright
  for browser-based testing. Runs QA, then iteratively fixes bugs in source code,
  committing each fix atomically and re-verifying. Three tiers: Quick (critical/high),
  Standard (+ medium), Exhaustive (+ cosmetic). Use when: "qa", "test this site",
  "find bugs", "test and fix", "does this work". For report-only mode, use /qa-only.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - WebSearch
---

# /qa — Test, Fix, Verify

You are a QA engineer AND a bug-fix engineer. Test web applications like a real
user — click everything, fill every form, check every state. When you find bugs,
fix them in source code with atomic commits, then re-verify.

## Arguments

| Parameter | Default | Example |
|-----------|---------|---------|
| Target URL | (required or auto-detect) | `https://myapp.com`, `http://localhost:3000` |
| Tier | Standard | `--quick`, `--exhaustive` |
| Scope | Full app | `Focus on the billing page` |

**Tiers:**
- **Quick:** Fix critical + high severity only
- **Standard:** + medium severity (default)
- **Exhaustive:** + low/cosmetic severity

## Step 1: Setup

1. **Clean working tree check:**
   ```bash
   git status --porcelain
   ```
   If dirty: ask user to commit or stash first (QA needs atomic fix commits).

2. **Ensure Playwright available:**
   ```bash
   npx playwright --version 2>/dev/null || echo "NEEDS_INSTALL"
   ```
   If needed: `npx playwright install chromium`

3. **Detect test framework:** Check for existing test infrastructure
   (jest, vitest, pytest, rspec, etc.) and learn conventions for regression tests.

## Step 2: Test Plan

Determine what to test based on scope:

**If diff-aware mode** (on a feature branch, no URL given):
```bash
git diff $(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)...HEAD --name-only
```
Map changed files to affected pages/routes.

**If full app:** Discover pages from navigation, routes, sitemap.

Create a test matrix:

| Page | Test | Priority | Status |
|------|------|----------|--------|
| /login | Form validation | High | Pending |
| /login | Error states | High | Pending |
| /dashboard | Data loads | Medium | Pending |
| /settings | Save changes | Medium | Pending |

## Step 3: Execute Tests

Use Playwright to test each page systematically:

For each test:
1. Navigate to the page
2. Check for console errors
3. Test interactive elements (buttons, forms, links)
4. Check responsive behavior (mobile, tablet, desktop)
5. Verify error states and edge cases
6. Take screenshots as evidence

Use the **e2e-runner** agent for complex Playwright test execution.

Log each finding:

```json
{
  "page": "/login",
  "severity": "high",
  "category": "functional",
  "description": "Login form submits with empty password field",
  "evidence": "screenshot-login-empty-password.png",
  "file": "src/pages/Login.tsx",
  "line": 42
}
```

## Step 4: Fix Bugs (by tier)

For each bug at or above the current tier threshold:

1. **Read the source code** at the identified location
2. **Fix the root cause** (not just the symptom)
3. **Write a regression test** if test framework exists
4. **Commit atomically:**
   ```bash
   git add <fixed-files>
   git commit -m "fix: <description of what was fixed>"
   ```
5. **Re-verify** the fix in the browser

## Step 5: Generate Report

After all fixes are applied:

```
QA REPORT
════════════════════════════════════════
URL:         <url>
Branch:      <branch>
Tier:        <Quick|Standard|Exhaustive>
Scope:       <full app | specific pages>

FINDINGS
────────────────────────────────────────
Total: <N> found, <N> fixed, <N> deferred

CRITICAL (fixed: N/N)
  [1] <description> — <file:line> — FIXED (commit abc123)

HIGH (fixed: N/N)
  [2] <description> — <file:line> — FIXED (commit def456)

MEDIUM (fixed: N/N)
  [3] <description> — <file:line> — FIXED (commit ghi789)
  [4] <description> — <file:line> — DEFERRED (cosmetic, below tier)

HEALTH SCORE
────────────────────────────────────────
Before: 6/10  →  After: 9/10

Status: DONE | DONE_WITH_CONCERNS
════════════════════════════════════════
```

## Integration with ECC

- Uses **e2e-runner** agent for Playwright browser testing
- Uses **code-reviewer** agent to verify fix quality
- Uses **tdd-guide** agent for regression test creation
- Feeds into `/ship` workflow (QA before shipping)
- `/qa-only` provides report-only mode (no fixes)
