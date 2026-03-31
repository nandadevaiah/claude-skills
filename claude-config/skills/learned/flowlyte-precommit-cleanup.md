# Flowlyte Pre-Commit Temp File Cleanup

**Extracted:** 2026-03-21
**Context:** When committing in the Flowlyte project and the pre-commit hook fails

## Problem
Pre-commit hook fails with: `[FAIL] Temporary files detected: ['backend/logs/app.log']`
The backend generates `app.log` during development, but the hook blocks commits if it exists.

## Solution
Remove the log file before committing:
```bash
rm -f backend/logs/app.log
```

## When to Use
When a git commit fails due to the repository health check detecting temporary files.
