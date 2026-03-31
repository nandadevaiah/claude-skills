---
name: autoplan
version: 1.0.0
description: |
  Auto-review pipeline. Runs CEO strategic review, architecture/eng review,
  and optionally design review sequentially with auto-decisions using 6
  decision principles. Surfaces only taste decisions (close calls, borderline
  scope) at a final approval gate. One command, fully reviewed plan out.
  Use when: "auto review", "autoplan", "run all reviews", "review this plan
  automatically", "full review pipeline", or "make the decisions for me".
benefits-from: [office-hours]
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - WebSearch
  - AskUserQuestion
  - Agent
---

# /autoplan — Auto-Review Pipeline

One command. Rough plan in, fully reviewed plan out.

Runs the full review gauntlet — CEO strategic review, engineering/architecture review,
and optionally design review — sequentially. Intermediate decisions are auto-resolved
using the 6 decision principles below. Only taste decisions (where reasonable people
could disagree) are surfaced for user approval at the end.

---

## The 6 Decision Principles

These rules auto-answer every intermediate question:

1. **Choose completeness** — Ship the whole thing. Pick the approach that covers more edge cases.
2. **Boil lakes** — Fix everything in the blast radius (files modified by this plan + direct importers). Auto-approve expansions that are in blast radius AND < 1 day effort (< 5 files, no new infra).
3. **Pragmatic** — If two options fix the same thing, pick the cleaner one. 5 seconds choosing, not 5 minutes.
4. **DRY** — Duplicates existing functionality? Reject. Reuse what exists.
5. **Explicit over clever** — 10-line obvious fix > 200-line abstraction. Pick what a new contributor reads in 30 seconds.
6. **Bias toward action** — Merge > review cycles > stale deliberation. Flag concerns but don't block.

**Conflict resolution (context-dependent tiebreakers):**
- **CEO phase:** P1 (completeness) + P2 (boil lakes) dominate.
- **Eng phase:** P5 (explicit) + P3 (pragmatic) dominate.
- **Design phase:** P5 (explicit) + P1 (completeness) dominate.

---

## Decision Classification

Every auto-decision is classified:

**Mechanical** — one clearly right answer. Auto-decide silently.

**Taste** — reasonable people could disagree. Auto-decide with recommendation, but surface at the final gate. Three natural sources:
1. **Close approaches** — top two are both viable with different tradeoffs.
2. **Borderline scope** — in blast radius but 3-5 files, or ambiguous radius.
3. **Agent disagreements** — different review perspectives recommend different things.

**User Challenge** — multiple reviewers agree the user's stated direction should change.
This is NEVER auto-decided. Goes to user with full context.

---

## Sequential Execution — MANDATORY

Phases MUST execute in strict order: CEO → Design (if UI) → Eng.
Each phase MUST complete fully before the next begins.
NEVER run phases in parallel — each builds on the previous.

---

## Phase 0: Intake

### Step 1: Read context

- Read `CLAUDE.md`, `DESIGN.md`, `TODOS.md` (if they exist)
- `git log --oneline -30` and `git diff origin/main --stat 2>/dev/null`
- Read any plan files referenced in the conversation

### Step 2: Detect UI scope

Grep the plan for view/rendering terms (component, screen, form, button, modal,
layout, dashboard, sidebar, nav, dialog). Require 2+ matches. If UI scope detected,
design review will be included.

### Step 3: Check for design doc

If no `DESIGN.md` or design doc exists, offer:
- A) Run `/office-hours` first to produce a design doc (sharper input for review)
- B) Skip — proceed with standard review

Output: "Here's what I'm working with: [plan summary]. UI scope: [yes/no].
Starting full review pipeline with auto-decisions."

---

## Phase 1: CEO Review (Strategy & Scope)

Use the **planner** agent to analyze strategic foundations, then apply
`/plan-ceo-review` methodology:

1. **Premise challenge:** Are the stated assumptions valid or just assumed?
   Name each premise and evaluate it. Present to user for confirmation.
   (This is the ONE question that is NOT auto-decided — premises require human judgment.)

2. **10-star framework:** What's the gap between 1-star and 10-star?

3. **Alternatives analysis:** Were alternatives dismissed too quickly?
   Table with 2-3 approaches, effort/risk/pros/cons.

4. **Scope decision:** Apply the 6 principles to determine:
   - Scope Expansion: build bigger
   - Selective Expansion: add one dimension
   - Hold Scope: polish what's planned
   - Scope Reduction: cut to sharpest wedge

5. **Risk assessment:** Technical, market, execution risks named explicitly.

Log every auto-decision with the principle used:
```
AUTO-DECISION: [description] → [choice] (Principle: P[N] — [name])
```

Mark taste decisions for the final gate.

---

## Phase 2: Design Review (if UI scope detected)

Skip if no UI changes detected.

1. **User flow analysis:** Map the user journey for each affected screen
2. **Interaction audit:** Forms, buttons, error states, loading states, empty states
3. **Responsiveness:** Mobile, tablet, desktop considerations
4. **Accessibility:** Keyboard navigation, screen readers, color contrast
5. **Consistency:** Does this match the existing design system/patterns?

Auto-decide using the 6 principles. Flag taste decisions.

---

## Phase 3: Eng Review (Architecture & Implementation)

Use the **architect** agent for structural analysis, then apply engineering review:

1. **Architecture review:**
   - Data flow diagram (what talks to what)
   - Dependency analysis (new dependencies justified?)
   - API design (if applicable)

2. **Code quality:**
   - Run **code-reviewer** agent on affected files
   - Run **security-reviewer** agent on auth/input/data access code
   - Check test coverage plan (use **tdd-guide** agent methodology)

3. **Edge cases:**
   - Error handling completeness
   - Race conditions / concurrency
   - Data migration (if schema changes)

4. **Performance:**
   - N+1 queries
   - Bundle size impact
   - Caching strategy

Auto-decide using the 6 principles (P5 explicit + P3 pragmatic dominate here).

---

## Phase 4: Final Approval Gate

Present ALL taste decisions and user challenges to the user in one batch:

```
AUTOPLAN REVIEW COMPLETE
════════════════════════════════════════

REVIEW SUMMARY
────────────────────────────────────────
CEO Review:     DONE — [N] decisions auto-resolved, [N] taste
Design Review:  DONE | SKIPPED (no UI scope)
Eng Review:     DONE — [N] decisions auto-resolved, [N] taste

AUTO-DECISIONS LOG
────────────────────────────────────────
[1] [description] → [choice] (P[N]: [principle])
[2] [description] → [choice] (P[N]: [principle])
...

TASTE DECISIONS (need your input)
────────────────────────────────────────
[T1] [description]
     Option A: [approach] — [tradeoff]
     Option B: [approach] — [tradeoff]
     RECOMMENDATION: [choice] because [reason]

[T2] [description]
     ...

USER CHALLENGES (models disagree with your direction)
────────────────────────────────────────
[UC1] What you said: [original direction]
      What reviewers recommend: [change]
      Why: [reasoning]
      If we're wrong, the cost is: [risk of changing]
      DEFAULT: Keep your original direction

UPDATED PLAN
────────────────────────────────────────
[Summary of all changes applied to the plan]

Status: DONE | DONE_WITH_CONCERNS
════════════════════════════════════════
```

If there are taste decisions, present via AskUserQuestion and let user approve
or override each one. Then update the plan accordingly.

---

## Integration with ECC

- **Orchestrates** existing skills: `/plan-ceo-review` → `/office-hours` → `/plan` (ECC planner)
- **Delegates to agents:** planner, architect, code-reviewer, security-reviewer, tdd-guide
- **Feeds into:** `/ship` workflow (plan is reviewed and ready to implement)
- **Replaces:** Running `/plan-ceo-review` + `/plan` + code review manually
- **Complements:** ECC's `/multi-plan` for multi-model collaborative planning
