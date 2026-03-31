---
name: canary
version: 1.0.0
description: |
  Post-deploy canary monitoring. Watches the live app for errors,
  performance regressions, and page failures. Takes periodic screenshots,
  compares against baselines, and alerts on anomalies. Uses Playwright
  for browser-based checks. Use when: "monitor deploy", "canary",
  "post-deploy check", "watch production", "verify deploy".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - AskUserQuestion
---

# /canary — Post-Deploy Monitoring

Watch the live app after a deploy for errors, performance regressions, and failures.
Runs for a configurable duration (default: 10 minutes) with periodic checks.

## Arguments
- `/canary <url>` — monitor the given URL
- `/canary <url> --duration 30m` — monitor for 30 minutes
- `/canary <url> --interval 60s` — check every 60 seconds (default: 30s)
- `/canary <url> --pages /,/dashboard,/api/health` — specific pages to check

## Step 1: Setup

Determine what to monitor:
1. If URL provided, use it
2. If deploy config exists in `CLAUDE.md` or `.deploy.json`, read production URL
3. Otherwise, ask user for the production URL

Ensure Playwright is available for browser-based checks.

## Step 2: Baseline capture

Before monitoring, capture initial state:
- HTTP status codes for all pages
- Response times
- Console errors (via Playwright)
- Screenshot of each page

## Step 3: Monitoring loop

Every `--interval` seconds:

1. **HTTP health:** `curl -sf -w "%{http_code} %{time_total}" <url>`
2. **Response time check:** Compare against baseline, flag >50% degradation
3. **Console errors:** Use Playwright to check for JavaScript errors
4. **Visual diff:** Screenshot and compare against baseline (flag major changes)
5. **API health:** Hit `/health` or `/api/health` endpoints

For each check, log:
```json
{"timestamp": "<ISO>", "page": "<url>", "status": 200, "response_ms": 145, "console_errors": 0, "visual_diff": false}
```

## Step 4: Alert on anomalies

If any check fails:
- HTTP 5xx → **ALERT: Server error detected**
- Response time >2x baseline → **WARNING: Performance degradation**
- New console errors → **WARNING: JavaScript errors detected**
- Health endpoint down → **ALERT: Health check failing**

On ALERT: immediately notify user and offer to rollback.

## Step 5: Report

After monitoring period ends:

```
CANARY REPORT
════════════════════════════════════════
URL:         <url>
Duration:    <start> to <end> (<N> minutes)
Checks:      <N> total, <N> passed, <N> warnings, <N> failures

Health:      STABLE | DEGRADED | FAILING
Uptime:      100% | <N>%
Avg Response: <N>ms (baseline: <N>ms)
Errors:      <N> console errors, <N> HTTP errors

Timeline:
  HH:MM  ✓ All checks passing
  HH:MM  ⚠ Response time +45% on /dashboard
  HH:MM  ✓ Recovered

Status:      DONE | DONE_WITH_CONCERNS
════════════════════════════════════════
```

## Integration with ECC

- Follows `/land-and-deploy` in the deployment pipeline
- Uses Playwright (same as **e2e-runner** agent) for browser checks
- Pairs with `/benchmark` for performance baseline comparison
- Can trigger `/investigate` if persistent errors are detected
