---
name: versa-call-analysis
description: Analyze a Versa Networks sales call transcript and produce a comprehensive HTML deal analysis document with deal snapshot, key quotes with translations, new intelligence, call performance review, competitive positioning, risk assessment, strategic recommendations, timeline, and action items. Also drafts a follow-up email. Trigger when the user pastes a call transcript for a Versa SASE sales engagement.
origin: custom
---

# Versa Call Analysis

Analyze a sales call transcript for a Versa Networks SASE engagement and produce a comprehensive, actionable HTML analysis document plus a follow-up email draft.

## When to Activate

- User pastes a call transcript and asks for analysis
- User says "analyze this call" or "review this transcript" in a Versa/SASE sales context
- User asks to "create a call analysis" for a prospect meeting
- User invokes `/versa-call-analysis`

## Inputs Required

Extract from the user's message and/or transcript:
- `[COMPANY NAME]` — the prospect organisation
- `[CALL NUMBER]` — which call this is in the sequence (Call 1, Call 2, etc.)
- `[CALL DATE]` — date of the call
- `[CALL TITLE]` — title or topic (e.g., "Tech Deep-Dive", "Discovery Call")
- `[CALL DURATION]` — length of the call
- `[CALL STAGE]` — deal stage (e.g., MQL/Prospecting, SQL, POC)
- `[VERSA TEAM]` — names and roles of Versa attendees
- `[PROSPECT TEAM]` — names and roles of prospect attendees
- `[CHANNEL PARTNER]` — if applicable, name and company
- `[FOLDERNAME]` — lowercased, no-spaces version of the company name for the output folder
- `[PRIOR CONTEXT]` — if previous call analyses or research.html exist in the same folder, READ them first to enable before/after comparison

## Execution

### Step 1 — Load Prior Context

Before analyzing the transcript:
1. Check if `C:/Projects/Versa/[FOLDERNAME]/` exists
2. If it does, read `research.html` and any prior `call*-analysis.html` files to understand what was known BEFORE this call
3. This prior context is critical for the "Deal Snapshot — Before vs After" comparison table and for identifying NEW intelligence vs already-known information

### Step 2 — Deep Transcript Analysis

Read the full transcript carefully. Extract:
1. **Every direct quote** that reveals buyer intent, objections, priorities, decision criteria, timeline, budget signals, or competitive intelligence. Record the timestamp.
2. **Use case details** — what the prospect actually uses today, what they need, what they explicitly said they DON'T need
3. **Decision process** — who decides, by when, what triggers the decision, what kills the deal
4. **Competitive intelligence** — what other vendors they're talking to, what pricing they've seen, what they liked/disliked
5. **Relationship dynamics** — who is the champion, who is the skeptic, who holds budget, who has veto power
6. **New technical details** — infrastructure, sites, users, bandwidth, specific products, integrations
7. **Agreed next steps** — what was committed to by each party
8. **What was NOT said** — topics that should have been raised but weren't, questions that weren't asked, pain points that weren't addressed

### Step 3 — Assess Call Performance

Evaluate the Versa team's performance honestly:
- **What went well** — moments that built trust, advanced the deal, or landed key messages
- **What needs improvement** — moments that confused, overshot, or missed the audience
- **Missed opportunities** — specific things that should have been said/shown but weren't
- Be specific and constructive. Cite timestamps. This is for internal learning, not for the prospect.

### Step 4 — Build the Analysis Document

Write a single self-contained HTML file to `C:/Projects/Versa/[FOLDERNAME]/call[N]-analysis.html`

### Step 5 — Draft Follow-Up Email

Write a follow-up email draft to `C:/Projects/Versa/[FOLDERNAME]/follow-up-email-call[N].md`

The email must:
- Be short (under 200 words body text)
- Summarize agreed next steps in bullet points
- Include a clear ask (info needed, meeting to schedule, etc.)
- Match the tone of the prospect (technical people want brevity, not sales language)
- NOT repeat the platform pitch or feature list
- Include one piece of differentiation not covered on the call (as a light touch, not a hard sell)
- Include notes to the sales team on WHY the email is written this way

## Required HTML Sections (in exact order)

### Section 1: Deal Snapshot — Updated After Call [N]

A comparison table with columns: **Parameter**, **Previous Understanding**, **Call [N] Update**

Parameters to compare (include all that are relevant):
- Primary Scope
- Use Case Complexity
- Hardware/Infrastructure Decisions
- SASE Decision Deadline
- Implementation Deadline
- Incumbent Vendor Dynamics
- Competitors & Status
- Decision Criteria (what will they decide on?)
- Next Step Agreed
- Quote/Commercial Requirements
- Budget Signals

Use `tag-red`, `tag-orange`, `tag-green` spans to highlight significant changes. Red = scope narrowed or risk increased. Green = positive signal. Orange = changed but neutral.

### Section 2: Key Quotes & What They Really Mean

Extract 6-10 of the most significant quotes from the transcript. For EACH quote:
- Use a callout box (colour-coded by sentiment)
- Format: **Speaker [timestamp]: "Exact quote"** in bold
- Below: **Translation:** — what this quote actually means for the deal in plain language
- Colour coding:
  - `callout-red` = negative signal, objection, risk, budget concern, no differentiation
  - `callout-orange` = caution, overshot pitch, mixed signal
  - `callout-green` = positive buying signal, champion behaviour, future intent
  - `callout-blue` = informational, personality insight, context

### Section 3: New Intelligence Gathered

Organize new information learned on this call into sub-sections:
- **Confirmed Use Case** — table with columns: Capability, Current Usage, Importance (Must Have / Nice to Have / Not Required) using coloured tags
- **Infrastructure Details (New)** — bullet list of specific technical details revealed
- **Vendor/Commercial Dynamics (New)** — bullet list of competitive and procurement intelligence
- **Anything else** relevant that was newly revealed

Only include genuinely NEW information. Do not repeat what was already in prior research/analysis documents.

### Section 4: Call Performance Review — Honest Assessment

Three sub-sections, each using a `grid-2` layout of callout boxes:
- **What Went Well** — `callout-green` boxes, one per positive moment
- **What Needs Improvement** — `callout-red` boxes, one per issue
- **Missed Opportunities** — `callout-orange` boxes, one per missed chance

Each box has a bold title and 2-3 sentences of specific, constructive feedback citing what happened and what should have happened instead.

### Section 5: Competitive Position After Call [N]

A table with columns: **Vendor**, **Status** (tag), **Strengths** (bullet list), **Weaknesses** (bullet list)

Include:
- The incumbent vendor
- Every active competitor mentioned in the call
- Versa Networks (label as "Us")
- Any eliminated competitors (marked as "Dead")

Status tags: `tag-green` for dead/eliminated, `tag-orange` for active/at risk, `tag-red` for ahead of us.

### Section 6: Deal Risk Assessment

4-6 callout boxes, each representing a risk or opportunity:
- `callout-red` = HIGH risk
- `callout-orange` = MEDIUM risk
- `callout-green` = OPPORTUNITY

Each box format:
- **RISK [N]: [Title] ([Severity])**
- 2-3 sentences explaining the risk
- **Mitigation:** — specific action to reduce the risk

OR for opportunities:
- **OPPORTUNITY: [Title]**
- 2-3 sentences explaining the opportunity
- **Action:** — specific action to capture it

### Section 7: Strategic Recommendations — How to Win This Deal

Sub-sections:
1. **The Honest Reality** — A `callout-blue` box with 3-4 sentences summarizing the true state of the deal without sugarcoating. What is the real decision dynamic?
2. **Immediate Actions (Next 5 Business Days)** — Numbered list of specific, time-bound actions with owners
3. **Demo Strategy (If applicable)** — What to show, what NOT to show, how long, who should drive
4. **Messaging Adjustments** — Table with columns: **Stop Saying**, **Start Saying**, **Why**. Be specific. Reference things actually said on the call that didn't work, and what should replace them.

### Section 8: Critical Path Timeline

A table with columns: **Date**, **Milestone**, **Owner**

Map out every date from now through deal close and implementation, including:
- Follow-up actions
- Quote delivery deadlines
- Prospect internal review periods
- Demo dates (if applicable)
- Decision deadlines
- Vendor renewal dates
- Implementation windows

### Section 9: Action Items

A table with columns: **#**, **Action**, **Owner**, **Due**, **Priority**

Priority uses tags: `tag-red` = Urgent, `tag-orange` = High, `tag-green` = Medium

List every committed action from the call plus recommended actions from the analysis.

## HTML Style Requirements

Use the **exact same CSS** as the versa-prospect-research skill. Copy it verbatim from the reference file at `C:/Projects/Versa/gama-aviation/call2-analysis.html` or from the versa-prospect-research skill template.

Key style rules:
- Self-contained: all CSS embedded inline, zero external dependencies
- Colour scheme: dark navy/white professional sales document
- CSS variables for primary (`#1a365d`), accent (`#2b6cb0`), and status colours
- Callout boxes with left border colour coding (red/orange/green/blue)
- Tables: alternating row colours, hover highlight, bold header row
- Tags: `tag-green`, `tag-red`, `tag-orange` for inline status indicators
- `grid-2` layout for side-by-side callout boxes (performance review section)
- Responsive and print-friendly (`@media print`)
- Include `blockquote` styling for quotes: `border-left:3px solid var(--accent); padding:8px 16px; background:#f8fafc; font-style:italic;`
- Header uses gradient background with call metadata

## Non-Negotiables

1. **Read prior context first**: Always check for existing research.html and prior call analyses before building the comparison table. If none exist, the "Previous Understanding" column should state "First Call — No Prior Data"
2. **Quotes must be exact**: Do not paraphrase. Pull the exact words from the transcript with timestamps
3. **Performance review must be honest**: This is for internal use. Don't soften negative feedback. The goal is to improve, not to feel good
4. **Recommendations must be specific**: "Follow up with pricing" is too vague. "Send 1-year and 3-year SSE-tier quote (SWG + CASB + ZTNA) to Mark by April 9, including separate CSG appliance line item per his request" is specific
5. **Every section must reference the transcript**: No generic SASE industry content. Every insight must trace back to something said (or not said) on this specific call
6. **Single file output**: One `.html` file for the analysis, one `.md` file for the follow-up email. No separate CSS files, no assets
7. **Versa positioning must be honest**: If the Versa pitch missed the mark, say so. If a competitor is genuinely ahead, say so. The analysis is useless if it's just cheerleading
8. **Follow-up email must be short**: Under 200 words. The prospect said what they want — give it to them without padding. Match their communication style (technical people want bullets, not paragraphs)

## HTML Template

The output HTML file MUST use the following structural template with the EXACT same CSS from the Versa prospect research skill:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>[COMPANY NAME] — Call [N] Analysis: [CALL TITLE] ([CALL DATE])</title>
<style>
  :root{--primary:#1a365d;--primary-light:#2d4a7a;--accent:#2b6cb0;--bg:#f7fafc;--white:#fff;--text:#1a202c;--text-light:#4a5568;--border:#e2e8f0;--red:#c53030;--red-bg:#fff5f5;--orange:#c05621;--orange-bg:#fffaf0;--green:#276749;--green-bg:#f0fff4;--blue:#2b6cb0;--blue-bg:#ebf8ff;--grey-bg:#f7fafc;--tag-green:#c6f6d5;--tag-green-text:#22543d;--tag-red:#fed7d7;--tag-red-text:#742a2a;--tag-orange:#feebc8;--tag-orange-text:#7b341e}
  *{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background:var(--bg);color:var(--text);line-height:1.6;font-size:15px}.container{max-width:1100px;margin:0 auto;padding:20px}.header{background:linear-gradient(135deg,var(--primary),var(--primary-light));color:var(--white);padding:40px;border-radius:12px;margin-bottom:30px}.header h1{font-size:1.8em;margin-bottom:5px}.header .subtitle{font-size:1.1em;opacity:.9;margin-bottom:15px}.header .meta{display:flex;gap:30px;font-size:.9em;opacity:.8;flex-wrap:wrap}.section{background:var(--white);border-radius:10px;padding:30px;margin-bottom:24px;box-shadow:0 1px 3px rgba(0,0,0,.08);border:1px solid var(--border)}.section h2{color:var(--primary);font-size:1.4em;margin-bottom:20px;padding-bottom:10px;border-bottom:2px solid var(--accent)}.section h3{color:var(--primary-light);margin:18px 0 10px;font-size:1.1em}table{width:100%;border-collapse:collapse;margin:15px 0;font-size:.95em}th{background:var(--primary);color:var(--white);padding:12px 15px;text-align:left;font-weight:600}td{padding:10px 15px;border-bottom:1px solid var(--border)}tr:nth-child(even){background:#f8fafc}tr:hover{background:#edf2f7}.callout{padding:16px 20px;border-radius:8px;margin:15px 0;border-left:4px solid}.callout-red{border-color:var(--red);background:var(--red-bg)}.callout-orange{border-color:var(--orange);background:var(--orange-bg)}.callout-green{border-color:var(--green);background:var(--green-bg)}.callout-blue{border-color:var(--blue);background:var(--blue-bg)}.callout strong{display:block;margin-bottom:4px}.question-card{background:var(--grey-bg);border:1px solid var(--border);border-radius:8px;padding:16px 20px;margin:12px 0}.question-card .question{font-weight:700;margin-bottom:6px}.question-card .rationale{font-style:italic;color:var(--text-light);font-size:.9em}.tag{display:inline-block;padding:3px 10px;border-radius:12px;font-size:.8em;font-weight:600;margin:2px}.tag-green{background:var(--tag-green);color:var(--tag-green-text)}.tag-red{background:var(--tag-red);color:var(--tag-red-text)}.tag-orange{background:var(--tag-orange);color:var(--tag-orange-text)}.grid-2{display:grid;grid-template-columns:1fr 1fr;gap:20px}.grid-3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px}.hook-card{background:linear-gradient(135deg,#ebf8ff,#f0fff4);border:1px solid var(--border);border-radius:8px;padding:16px;margin:10px 0}.hook-card .label{font-weight:700;color:var(--accent);font-size:.85em;text-transform:uppercase;margin-bottom:6px}ul,ol{padding-left:24px}li{margin:4px 0}blockquote{border-left:3px solid var(--accent);padding:8px 16px;margin:10px 0;background:#f8fafc;font-style:italic;color:var(--text-light)}@media print{body{font-size:12px}.container{max-width:100%;padding:0}.section{box-shadow:none;break-inside:avoid}.header{background:var(--primary)!important;-webkit-print-color-adjust:exact;print-color-adjust:exact}}@media(max-width:768px){.grid-2,.grid-3{grid-template-columns:1fr}.header{padding:24px}}
</style>
</head>
<body>
<div class="container">
  <!-- Header: Call title, company, metadata (date, duration, stage, attendees) -->
  <!-- Section 1: Deal Snapshot — comparison table -->
  <!-- Section 2: Key Quotes — callout boxes with timestamps and translations -->
  <!-- Section 3: New Intelligence — use case table, infrastructure bullets, vendor dynamics -->
  <!-- Section 4: Call Performance Review — grid-2 callout boxes: went well, needs improvement, missed opportunities -->
  <!-- Section 5: Competitive Position — vendor comparison table with tags -->
  <!-- Section 6: Deal Risk Assessment — callout boxes: red=high risk, orange=medium, green=opportunity -->
  <!-- Section 7: Strategic Recommendations — reality check, immediate actions, demo strategy, messaging table -->
  <!-- Section 8: Critical Path Timeline — date/milestone/owner table -->
  <!-- Section 9: Action Items — #/action/owner/due/priority table -->
  <!-- Footer: "Prepared for Versa Networks • [DATE] • Confidential — For internal sales use only" -->
</div>
</body>
</html>
```

## Example Trigger Phrases

- "Here's the transcript from the second call with Gama Aviation, analyze it"
- "Review this call transcript and create an analysis"
- "/versa-call-analysis"
- "Analyze this Versa sales call and tell me how to win"
- "Create a call analysis for [company] — here's the transcript"
