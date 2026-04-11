---
description: Analyze a Versa Networks sales call transcript and produce a comprehensive HTML deal analysis document plus a follow-up email draft.
---

# /versa-call-analysis

## Purpose

Turn a raw Versa Networks SASE sales call transcript into a comprehensive, actionable HTML deal analysis — with deal snapshot comparison, exact quotes and translations, new intelligence, honest call performance review, competitive positioning, risk assessment, strategic recommendations, timeline, and action items. Also drafts a short follow-up email matched to the prospect's tone.

## Usage

```
/versa-call-analysis [company] [call number] [paste transcript]
```

Examples:
- `/versa-call-analysis Gama Aviation Call 2` followed by pasted transcript
- `/versa-call-analysis` followed by pasted transcript (prompts for metadata)
- "Here's the transcript from the second call with Gama Aviation, analyze it"
- "Review this Versa call transcript and create an analysis"

If the transcript or metadata is missing, ask the user for:
- Company name, call number, call date, call title, call duration, call stage
- Versa team attendees and prospect team attendees
- Channel partner (if any)
- Output folder name (lowercased, no spaces)

## Workflow

1. **Load the skill** — Read the skill file at `.claude/skills/versa-call-analysis/SKILL.md` for the full execution spec (required HTML sections, CSS, non-negotiables, template).
2. **Load prior context** — Check `C:/Projects/Versa/[FOLDERNAME]/` for existing `research.html` and any prior `call*-analysis.html` files. These drive the "Before vs After" comparison and let you flag genuinely NEW intelligence.
3. **Deep transcript analysis** — Extract every significant direct quote with timestamps, use case details, decision process, competitive intelligence, relationship dynamics, new technical details, agreed next steps, and what was NOT said.
4. **Honest performance review** — Cite timestamps. What went well, what needs improvement, what was missed. No sugarcoating — this is for internal learning.
5. **Build the HTML file** — Write a single self-contained HTML file at `C:/Projects/Versa/[FOLDERNAME]/call[N]-analysis.html` using the exact 9-section structure and CSS specified in the skill.
6. **Draft follow-up email** — Write a short (<200 word) follow-up email at `C:/Projects/Versa/[FOLDERNAME]/follow-up-email-call[N].md`, matched to the prospect's tone, with one piece of light differentiation, plus notes to the sales team on WHY the email is written that way.

## Output

Two files in `C:/Projects/Versa/[FOLDERNAME]/`:

1. **`call[N]-analysis.html`** — Self-contained HTML (embedded CSS, no external assets) with 9 sections:
   1. Deal Snapshot — Before vs After comparison table
   2. Key Quotes & What They Really Mean (6–10 colour-coded callouts with translations)
   3. New Intelligence Gathered
   4. Call Performance Review — Honest Assessment
   5. Competitive Position After Call
   6. Deal Risk Assessment
   7. Strategic Recommendations — How to Win This Deal
   8. Critical Path Timeline
   9. Action Items

2. **`follow-up-email-call[N].md`** — Short email draft under 200 words with bullet-point next steps, a clear ask, one differentiation touch, and sales-team notes on tone rationale.

## Non-Negotiables

- Exact quotes with timestamps — no paraphrasing
- Honest performance review — no cheerleading
- Every insight traces to something said (or not said) on this specific call
- Single-file HTML output, no separate CSS or assets
- Follow-up email under 200 words, matched to prospect's communication style
