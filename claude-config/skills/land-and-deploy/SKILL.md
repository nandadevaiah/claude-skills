---
name: land-and-deploy
version: 1.0.0
description: |
  Land and deploy. Merges PR, waits for CI and deploy, verifies production
  health via canary checks. One command from approval to production verification.
  Use when: "land it", "merge and deploy", "ship to prod", "deploy this PR".
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# /land-and-deploy — Merge, Deploy, Verify

One command from PR approval to verified production deployment.

## Step 0: Detect platform and PR

```bash
git remote get-url origin 2>/dev/null
```

Detect platform (GitHub/GitLab) and find the current PR/MR:

**GitHub:**
```bash
gh pr view --json number,state,mergeable,title,url -q '{number,state,mergeable,title,url}'
```

**GitLab:**
```bash
glab mr view -F json 2>/dev/null
```

If no PR/MR found: "No PR found for this branch. Run `/ship` first to create one."

---

## Step 1: Pre-merge checks

1. **CI status:** Check all CI checks are passing
   - GitHub: `gh pr checks`
   - GitLab: `glab mr view -F json` and check pipeline status

2. **Review status:** Check PR is approved
   - GitHub: `gh pr view --json reviewDecision -q .reviewDecision`
   - GitLab: check approval status

3. If checks failing or not approved: **STOP** and report what's blocking.

---

## Step 2: Merge

**GitHub:**
```bash
gh pr merge --squash --delete-branch
```

**GitLab:**
```bash
glab mr merge --squash --remove-source-branch --yes
```

If merge fails (conflicts, branch protection): report the error.

---

## Step 3: Wait for deploy

Read deploy configuration from `CLAUDE.md` or `.deploy.json`. If not found, ask user:
- What's the production URL?
- How is the app deployed? (Vercel, Fly.io, Render, GitHub Actions, manual)
- How long does deploy typically take?

Poll for deploy completion:
1. Check CI/CD pipeline status (GitHub Actions, GitLab CI)
2. Poll the production URL health endpoint
3. Wait up to 10 minutes, checking every 30 seconds

---

## Step 4: Canary verification

Once deployed, run basic health checks:

1. **HTTP health:** `curl -sf <prod-url>/health` or `curl -sf <prod-url>`
2. **Response time:** Measure and compare against baseline
3. **Error check:** Look for 5xx responses on key pages

If health checks fail: **STOP** and alert immediately.

---

## Step 5: Report

```
DEPLOY REPORT
════════════════════════════════════════
PR:          <url>
Merged:      <branch> → <base>
Deploy:      <platform> — completed at <time>
Health:      PASS | FAIL
Response:    <avg-ms> (baseline: <baseline-ms>)
Status:      DONE | DONE_WITH_CONCERNS
════════════════════════════════════════
```

If `DONE_WITH_CONCERNS`: list each concern (slow response, warnings in logs, etc.)

## Integration with ECC

- Follows `/ship` in the deployment pipeline
- Uses deploy config from `/setup-deploy`
- Triggers `/canary` for extended monitoring if concerns are found
- Works alongside existing `/verify` command for pre-deploy checks
