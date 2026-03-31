---
name: qa-only
version: 1.0.0
description: |
  Report-only QA testing. Same methodology as /qa but produces a structured
  bug report without making any code changes. Use when you want to assess
  quality without fixing, or when someone else will handle the fixes.
  Use when: "qa report", "audit the site", "find bugs but don't fix",
  "quality assessment", "test report".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

# /qa-only — Report-Only QA

Same testing methodology as `/qa`, but **read-only**. No code changes, no commits,
no fixes. Produces a structured bug report.

## Arguments

Same as `/qa`:
- `/qa-only <url>` — test the given URL
- `/qa-only <url> --quick` — critical + high only
- `/qa-only <url> --exhaustive` — include cosmetic issues
- `/qa-only <url> --scope "billing page"` — focus area

## Process

Follow the same testing process as `/qa` (Steps 1-3):
1. Setup and Playwright check
2. Test plan creation
3. Systematic testing with evidence collection

**Skip Step 4** (no fixes applied).

## Output

Generate a detailed bug report:

```
QA REPORT (READ-ONLY)
════════════════════════════════════════
URL:         <url>
Branch:      <branch>
Tested:      <date>

FINDINGS BY SEVERITY
────────────────────────────────────────

CRITICAL (<N>)
  [1] <description>
      Page: <url>  |  Expected: <X>  |  Actual: <Y>
      Likely file: <file:line>
      Screenshot: <path>

HIGH (<N>)
  [2] <description>
      Page: <url>  |  Expected: <X>  |  Actual: <Y>
      Likely file: <file:line>

MEDIUM (<N>)
  [3] <description>
      Page: <url>  |  Expected: <X>  |  Actual: <Y>
      Likely file: <file:line>

LOW (<N>)
  [4] <description>

HEALTH SCORE: <N>/10

RECOMMENDED FIX ORDER:
  1. [Critical #1] — <reason for priority>
  2. [High #2] — <reason>
  3. [Medium #3] — <reason>

════════════════════════════════════════
```

Save report to `.qa-reports/{date}-qa-report.md`.

## Integration with ECC

- Same testing approach as `/qa` but non-destructive
- Use when delegating fixes to another team member
- Report can feed into issue trackers (GitHub Issues, Linear, etc.)
- Pair with `/investigate` for deep-diving specific bugs from the report
