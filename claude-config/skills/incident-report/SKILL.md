---
name: incident-report
description: Generate a structured technical incident report from the current session's work and save it to technical_documentation/. Use after fixing a bug, data issue, or production incident, or when asked to write a post-mortem documenting what broke, the root cause, and the fix.
origin: ECC
---

# Incident Report Generator

Generate a structured technical incident report from the current session's work and save it to `technical_documentation/`.

## When to Use

- After fixing a bug, data issue, or production incident
- When asked to document what was fixed and why
- Post-mortem documentation for future reference

## Workflow

1. **Ensure output directory exists**: Create `technical_documentation/` at the project root if missing.

2. **Gather context from the current session**:
   - Read `git log` for recent commits on the current branch
   - Read `git diff` of the relevant commits to understand what changed
   - Identify the files modified, the root cause, and the fix applied

3. **Generate the report** using the template below. Fill every section from the session context. Be specific — include file paths, line numbers, code snippets, and data flow traces.

4. **Save the report** as `technical_documentation/INC-{YYYYMMDD}-{short-slug}.md` (e.g., `INC-20260404-stale-ticker-price.md`).

5. **Commit the report** with message `docs(incident): INC-{YYYYMMDD}-{short-slug}`.

## Report Template

```markdown
# Incident Report: {Title}

| Field | Value |
|-------|-------|
| **ID** | INC-{YYYYMMDD}-{seq} |
| **Date** | {YYYY-MM-DD} |
| **Severity** | {Critical / High / Medium / Low} |
| **Status** | Resolved |
| **Author** | {git user} |
| **Commit(s)** | {short SHA(s)} |

---

## Summary

{1-2 sentence description of what went wrong and what the user experienced.}

## Impact

{Who/what was affected. Scope of the issue — all users, specific tickers, specific pages, etc.}

## Timeline

| Time | Event |
|------|-------|
| {when} | {what happened} |

## Root Cause Analysis

{Detailed technical explanation of WHY the bug occurred. Trace the data flow from source to display. Include file paths and line numbers.}

### Data Flow

{Step-by-step trace showing how data moves through the system and where it breaks.}

## Fix Applied

{What was changed and why. Reference specific files and line numbers.}

### Files Modified

| File | Change |
|------|--------|
| {path} | {description} |

### Key Code Changes

{Show the critical before/after code snippets that represent the fix.}

## Prevention

{What was added to prevent recurrence — validation, fallbacks, guards, tests.}

## Lessons Learned

{Non-obvious takeaways that would help future debugging of similar issues.}
```

## Guidelines

- Be precise: use actual file paths, line numbers, variable names
- Include code snippets for the root cause AND the fix
- Explain the "why" — not just what broke, but the chain of assumptions that led to it
- Keep it scannable: use tables, bullet points, and headers
- The audience is a developer who will encounter a similar issue in 6 months
