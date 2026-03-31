# Pre-Merge Verification

Run the full pre-merge checklist for merging `version-2.0` → `main`.

## Instructions

Execute verification in parallel where possible:

### Phase 1: Automated Checks (parallel)

Launch these simultaneously:

**Agent 1 — Build, Tests, and Infrastructure:**
Run `./scripts/pre_merge_check.sh` from the project root. This covers:
- Frontend build (`npm run build`)
- Backend tests (`pytest backend/tests/`)
- Git status and branch state
- Staging service health check
- Production env var verification
- Database migration verification via Supabase REST API
- Merge diff summary

**Agent 2 — E2E Smoke Tests (if `$ARGUMENTS` includes `e2e`):**
Use the **e2e-runner** agent to run Playwright smoke tests against the staging URL (`https://flowlyt-staging-217325609840.us-central1.run.app`):
- Landing page loads
- Login page renders
- `/api/health` returns 200
- Dashboard renders after login (if test credentials available)

### Phase 2: Results

Combine results from both agents into a single report:

```
PRE-MERGE VERIFICATION: [PASS/FAIL]

Build:          [OK/FAIL]
Tests:          [X/Y passed]
Git:            [clean/uncommitted changes]
Staging:        [live/down] — URL
Prod Env Vars:  [X/Y set]
Migrations:     [verified/issues]
E2E Smoke:      [X/Y passed] (if run)

Manual checks still required:
- [ ] Stripe webhook endpoint
- [ ] Stripe price objects ($59/mo, $590/yr)
- [ ] Test checkout with Stripe test card
- [ ] Sign-off
```

If any FAIL items, list them with fix suggestions.

### Phase 3: Offer Next Steps

Based on results, offer:
- If all pass: "Ready to create PR? (`gh pr create --base main --head version-2.0`)"
- If failures: List fixes needed before merge

## Arguments

$ARGUMENTS can be:
- (empty) — Run script checks only (fast, ~30 seconds)
- `e2e` — Also run Playwright smoke tests against staging (~2-3 minutes)
- `--skip-db` — Skip database migration checks
- `--staging-only` — Only verify staging deployment
