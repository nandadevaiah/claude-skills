---
name: benchmark
version: 1.0.0
description: |
  Performance regression detection. Establishes baselines for page load times,
  Core Web Vitals, and resource sizes. Compares before/after on every PR.
  Tracks performance trends over time. Uses Playwright for browser metrics.
  Use when: "performance", "benchmark", "page speed", "web vitals",
  "bundle size", "load time".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - AskUserQuestion
---

# /benchmark — Performance Regression Detection

You are a **Performance Engineer**. Performance doesn't degrade in one big regression,
it dies by a thousand paper cuts. Each PR adds 50ms here, 20KB there, and one day
the app takes 8 seconds to load.

Your job: measure, baseline, compare, and alert.

## Arguments
- `/benchmark <url>` — full performance audit with baseline comparison
- `/benchmark <url> --baseline` — capture baseline (run before making changes)
- `/benchmark <url> --quick` — single-pass timing check (no baseline needed)
- `/benchmark <url> --pages /,/dashboard,/api/health` — specify pages
- `/benchmark --diff` — benchmark only pages affected by current branch
- `/benchmark --trend` — show performance trends from historical data

## Phase 1: Setup

```bash
mkdir -p .benchmark/reports .benchmark/baselines
```

Ensure Playwright is available:
```bash
npx playwright --version 2>/dev/null || echo "NEEDS_INSTALL"
```

If `NEEDS_INSTALL`: ask user to run `npx playwright install chromium`.

## Phase 2: Page Discovery

If `--pages` specified, use those. Otherwise, auto-discover from the app's navigation
or use common defaults: `/`, `/login`, `/dashboard`, `/api/health`.

If `--diff` mode:
```bash
git diff $(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)...HEAD --name-only
```
Map changed files to affected routes.

## Phase 3: Performance Data Collection

For each page, use Playwright to collect real performance metrics:

```bash
npx playwright test --reporter=json -c /dev/null <<'SCRIPT'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('<PAGE_URL>', { waitUntil: 'networkidle' });
  const timing = JSON.parse(await page.evaluate(() =>
    JSON.stringify(performance.getEntriesByType('navigation')[0])
  ));
  const resources = JSON.parse(await page.evaluate(() =>
    JSON.stringify(performance.getEntriesByType('resource')
      .map(r => ({name: r.name.split('/').pop().split('?')[0], type: r.initiatorType, size: r.transferSize, duration: Math.round(r.duration)}))
      .sort((a,b) => b.duration - a.duration).slice(0,15))
  ));
  console.log(JSON.stringify({timing, resources}));
  await browser.close();
})();
SCRIPT
```

Extract key metrics:
- **TTFB** (Time to First Byte): `responseStart - requestStart`
- **FCP** (First Contentful Paint): from paint entries
- **DOM Interactive**: `domInteractive - navigationStart`
- **DOM Complete**: `domComplete - navigationStart`
- **Full Load**: `loadEventEnd - navigationStart`

## Phase 4: Baseline Capture (--baseline mode)

Save metrics to `.benchmark/baselines/baseline.json`:

```json
{
  "url": "<url>",
  "timestamp": "<ISO>",
  "branch": "<branch>",
  "pages": {
    "/": {
      "ttfb_ms": 120,
      "fcp_ms": 450,
      "dom_interactive_ms": 600,
      "dom_complete_ms": 1200,
      "full_load_ms": 1400,
      "total_requests": 42,
      "total_transfer_bytes": 1250000,
      "js_bundle_bytes": 450000,
      "css_bundle_bytes": 85000
    }
  }
}
```

## Phase 5: Comparison

If baseline exists, compare current metrics:

```
PERFORMANCE REPORT — [url]
══════════════════════════
Branch: [current] vs baseline ([baseline-branch])

Page: /
─────────────────────────────────────────────────────
Metric              Baseline    Current     Delta    Status
TTFB                120ms       135ms       +15ms    OK
FCP                 450ms       480ms       +30ms    OK
DOM Complete        1200ms      1350ms      +150ms   WARNING
Full Load           1400ms      2100ms      +700ms   REGRESSION
JS Bundle           450KB       720KB       +270KB   REGRESSION
```

**Regression thresholds:**
- Timing: >50% increase OR >500ms absolute = REGRESSION
- Timing: >20% increase = WARNING
- Bundle size: >25% increase = REGRESSION
- Bundle size: >10% increase = WARNING
- Request count: >30% increase = WARNING

## Phase 6: Performance Budget Check

```
PERFORMANCE BUDGET CHECK
════════════════════════
Metric              Budget      Actual      Status
FCP                 < 1.8s      0.48s       PASS
Total JS            < 500KB     720KB       FAIL
Total CSS           < 100KB     88KB        PASS
Total Transfer      < 2MB       1.8MB       WARNING
HTTP Requests       < 50        58          FAIL

Grade: B (3/5 passing)
```

## Phase 7: Trend Analysis (--trend mode)

Load historical baselines and show trends:

```
PERFORMANCE TRENDS (last 5 benchmarks)
══════════════════════════════════════
Date        FCP     Bundle    Requests    Grade
2026-03-10  420ms   380KB     38          A
2026-03-14  450ms   450KB     42          A
2026-03-18  480ms   720KB     58          B

TREND: JS bundle growing 50KB/week. Investigate.
```

## Phase 8: Save Report

Write to `.benchmark/reports/{date}-benchmark.md` and `.benchmark/reports/{date}-benchmark.json`.

## Important Rules

- **Measure, don't guess.** Use actual performance.getEntries() data.
- **Baseline is essential.** Without it, report absolute numbers but can't detect regressions.
- **Relative thresholds, not absolute.** 2000ms is fine for a dashboard, terrible for a landing page.
- **Third-party scripts are context.** Flag them, but focus on first-party resources.
- **Bundle size is the leading indicator.** Load time varies with network. Bundle size is deterministic.
- **Read-only.** Produce the report. Don't modify code unless explicitly asked.

## Integration with ECC

- Use before `/ship` to catch performance regressions pre-merge
- Pairs with the **e2e-runner** agent for browser-based metrics
- Results feed into `/ship` PR description for reviewer context
