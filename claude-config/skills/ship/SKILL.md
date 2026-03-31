---
name: ship
version: 1.0.0
description: |
  Ship workflow: detect + merge base branch, run tests, review diff, update
  CHANGELOG, commit, push, create PR. Use when asked to "ship", "deploy",
  "push to main", "create a PR", "merge and push", or "get it deployed".
  Proactively invoke when the user says code is ready, asks about deploying,
  wants to push code up, or asks to create a PR.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
---

# /ship — Automated Ship Workflow

You are running the `/ship` workflow. This is a **non-interactive, fully automated**
workflow. Do NOT ask for confirmation at most steps. The user said `/ship` — DO IT.
Run straight through and output the PR URL at the end.

**Only stop for:**
- On the base branch (abort)
- Merge conflicts that can't be auto-resolved
- Test failures introduced by this branch
- Review findings that need user judgment
- BREAKING changes requiring manual version bump decision

**Never stop for:**
- Uncommitted changes (always include them)
- CHANGELOG content (auto-generate from diff)
- Commit message approval (auto-commit)

---

## Step 0: Detect platform and base branch

```bash
git remote get-url origin 2>/dev/null
```

- If URL contains "github.com" → platform is **GitHub** (use `gh`)
- If URL contains "gitlab" → platform is **GitLab** (use `glab`)
- Otherwise: check CLI availability (`gh auth status`, `glab auth status`)
- Fallback: git-native commands only

Detect base branch:
1. `gh pr view --json baseRefName -q .baseRefName 2>/dev/null` (if GitHub)
2. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null`
3. `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`
4. Fallback: try `origin/main`, then `origin/master`, then `main`

---

## Step 1: Pre-flight

1. Check current branch. If on base branch, **abort**: "Ship from a feature branch."

2. `git status` (never use `-uall`). Uncommitted changes are always included.

3. `git diff <base>...HEAD --stat` and `git log <base>..HEAD --oneline` to understand what's shipping.

---

## Step 2: Merge base branch (BEFORE tests)

```bash
git fetch origin <base> && git merge origin/<base> --no-edit
```

If merge conflicts: try auto-resolve simple ones (VERSION, lock files, CHANGELOG ordering).
If complex: **STOP** and show them.

If already up to date: continue silently.

---

## Step 3: Run tests

Detect the test command from project config:
- Read `CLAUDE.md` for test commands
- Check `package.json` scripts, `Makefile`, `Gemfile`, `pyproject.toml`
- Common: `npm test`, `bun test`, `pytest`, `go test ./...`, `cargo test`, `bundle exec rspec`

Run the full test suite. If tests fail:
1. Check if failures are pre-existing: `git stash && <test-command> && git stash pop`
2. If pre-existing: note in PR body, continue
3. If introduced by this branch: **STOP**, show failures, offer to fix

---

## Step 3.5: Pre-landing code review

Use the **code-reviewer** agent to review the diff:
```bash
git diff <base>...HEAD
```

Categories:
- **AUTO-FIX:** Dead code, stale comments, obvious N+1 queries — fix and commit automatically
- **ASK:** Security issues, architectural concerns, incomplete error handling — present to user
- **INFO:** Style suggestions, nice-to-haves — note in PR body only

Also run **security-reviewer** agent on any files touching auth, input handling, or data access.

---

## Step 4: Version bump (if applicable)

Check if project uses semantic versioning:
```bash
[ -f VERSION ] || [ -f package.json ] && echo "HAS_VERSION" || echo "NO_VERSION"
```

If versioned: auto-bump PATCH for fixes, MINOR for features (detect from commit messages).
If BREAKING changes detected: **ask** user for version bump decision.

---

## Step 5: CHANGELOG update

If `CHANGELOG.md` exists, auto-generate entry from the diff:
1. Read all commits: `git log <base>..HEAD --oneline`
2. Read the full diff: `git diff <base>...HEAD`
3. Write user-facing release notes (what changed, not implementation details)
4. Prepend to CHANGELOG.md

---

## Step 6: Commit, push, create PR

1. Stage all changes: `git add -A`
2. Commit with descriptive message following conventional commits format
3. Push: `git push -u origin HEAD`
4. Create PR:

**If GitHub:**
```bash
gh pr create --title "<type>: <description>" --body "$(cat <<'EOF'
## Summary
<bullet points from diff analysis>

## Test plan
- [ ] All tests passing
- [ ] Code review completed
- [ ] No security issues found

## Review status
- Code review: <result>
- Security review: <result>
- Test coverage: <result>
EOF
)"
```

**If GitLab:** use `glab mr create` with equivalent format.

5. Output the PR/MR URL.

---

## Completion Status

Report:
```
SHIP REPORT
════════════════════════════════════════
Branch:      <branch> → <base>
Tests:       PASS (N tests)
Review:      <N> auto-fixed, <N> flagged
Version:     <old> → <new>
PR:          <URL>
Status:      DONE | DONE_WITH_CONCERNS
════════════════════════════════════════
```

## Integration with ECC

- Uses **code-reviewer** agent for pre-landing review
- Uses **security-reviewer** agent for security-sensitive changes
- Complements `/investigate` for debugging before shipping
- Feeds into `/land-and-deploy` for the full deploy pipeline
- Works with existing `/pre-merge-check` command
