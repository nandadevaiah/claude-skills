---
name: versa-prospect-research
description: Research a prospect company and contact for a Versa SASE sales meeting. Produces a self-contained HTML research document covering company profile, contact background, discovery questions, SASE use cases, competitive positioning, and meeting strategy. Trigger when the user asks to research a company and/or person for a Versa sales meeting or call.
origin: custom
---

# Versa Prospect Research

Generate a complete, consistent sales research document for any prospect meeting.

## When to Activate

- User says "research [company] for a meeting with [person]"
- User says "I'm meeting [name] at [company], help me prepare"
- User mentions a company name + contact name + Versa or SASE context
- User asks for "prospect research" or "account research" for Versa

## Inputs Required

Collect from the user's message:
- `[COMPANY NAME]` - the prospect organisation
- `[CONTACT NAME]` - the person they are meeting
- `[CONTACT TITLE]` - their role (if provided; research it if not)
- `[FOLDERNAME]` - lowercased, no spaces version of the company name for the output folder (e.g. `dbcargo`, `aveva`, `siemens`)

## Execution

Run three research agents **in parallel**, then synthesise into a single HTML file.

### Agent 1 — Company Research

Search for:
- Company overview: parent company, HQ, employee count, revenue, countries of operation
- Industry, sector, and key business activities
- IT/OT environment: known cloud strategy, technology stack, IoT, OT/ICS systems
- Digital transformation and cybersecurity initiatives
- Recent news (last 12 months): incidents, restructuring, partnerships, M&A, regulatory actions
- Financial performance and any existential pressures
- Regulatory exposure: NIS2, GDPR, sector-specific directives
- Key industry competitors

### Agent 2 — Contact Research

Search for:
- Current title and organisation (including any subsidiary distinctions)
- Reporting structure (who they report to)
- Previous roles and career trajectory
- LinkedIn profile or professional bio
- Published articles, conference talks, or interviews
- Professional focus areas inferred from role and employer
- Try multiple spelling variations of the name if needed

### Agent 3 — Versa SASE Positioning

Research and compile:
- How Versa SASE maps specifically to this company's industry and infrastructure
- Recent Versa product launches relevant to this account's challenges
- Competitive comparison tailored to the account: Versa vs. Zscaler, Palo Alto Prisma, Fortinet
- Specific use cases for their environment (OT/IT convergence, sovereign SASE, ZTNA, SD-WAN, etc.)

## Output

Create folder `~/projects/Versa/[FOLDERNAME]/` and write a single `research.html` file.

### Required Sections (in order)

1. **Header** — company name, contact name and title, date prepared
2. **Contact Profile** — role, reporting line, background, focus areas, key context callout box
3. **Company Overview** — key facts table, business units list, IT/OT environment table
4. **Critical News & Context** — callout boxes for recent events (colour-coded by severity)
5. **Discovery Questions** — exactly 12 questions grouped into 4 themes:
   - Current Security Architecture (3 questions)
   - Operational Challenges (3 questions)
   - Compliance & Regulatory (3 questions)
   - Future & Innovation (3 questions)
   - Each question has a **Rationale** in italic explaining why to ask it
6. **How [COMPANY] Can Leverage Versa SASE** — 6-7 use cases written for their specific environment
7. **Competitive Positioning** — comparison table (Versa vs Zscaler, Palo Alto, Fortinet) with colour-coded tags, plus a per-competitor weakness card
8. **Meeting Strategy** — opening hooks (3 options), key messages for this contact's persona, objection handling (3 common objections with responses), suggested next steps
9. **Appendix** — industry competitors table

### HTML Style Requirements

- Self-contained: all CSS embedded inline, zero external dependencies
- Colour scheme: dark navy/white professional sales document
- CSS variables for primary (`#1a365d`), accent (`#2b6cb0`), and status colours
- Callout boxes with left border colour coding:
  - Red (`#c53030`) — critical: security incidents, existential risks
  - Orange (`#c05621`) — warning: financial pressure, deadlines, compliance gaps
  - Green (`#276749`) — positive: opportunities, strengths
  - Blue (`#2b6cb0`) — informational: context, background
- Tables: alternating row colours, hover highlight, bold header row
- Question cards: grey background, bold question text, italic rationale
- Competitive tags: green = Versa advantage, red = competitor weakness, orange = partial
- Competitor weakness cards: grid layout, one card per competitor
- Responsive two-column layout where appropriate
- Print-friendly (`@media print`)

## Non-Negotiables

1. **Parallel agents**: always run all three research agents simultaneously, not sequentially
2. **Specificity**: every section must reference actual details from the research — no generic boilerplate
3. **Contact persona awareness**: tailor meeting strategy tone to the contact's seniority and technical level (engineer vs. CISO vs. CIO vs. business exec)
4. **Consistency**: every output must follow the exact section order and HTML structure above
5. **Single file**: output is always one `research.html` — no separate CSS files, no assets folder

## HTML Template

The output HTML file MUST use the following exact CSS and structural template. Do NOT deviate from this format — it ensures visual consistency across all Versa prospect research documents.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Versa Prospect Research — [COMPANY NAME]</title>
<style>
  :root{--primary:#1a365d;--primary-light:#2d4a7a;--accent:#2b6cb0;--bg:#f7fafc;--white:#fff;--text:#1a202c;--text-light:#4a5568;--border:#e2e8f0;--red:#c53030;--red-bg:#fff5f5;--orange:#c05621;--orange-bg:#fffaf0;--green:#276749;--green-bg:#f0fff4;--blue:#2b6cb0;--blue-bg:#ebf8ff;--grey-bg:#f7fafc;--tag-green:#c6f6d5;--tag-green-text:#22543d;--tag-red:#fed7d7;--tag-red-text:#742a2a;--tag-orange:#feebc8;--tag-orange-text:#7b341e}
  *{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;background:var(--bg);color:var(--text);line-height:1.6;font-size:15px}.container{max-width:1100px;margin:0 auto;padding:20px}.header{background:linear-gradient(135deg,var(--primary),var(--primary-light));color:var(--white);padding:40px;border-radius:12px;margin-bottom:30px}.header h1{font-size:2em;margin-bottom:5px}.header .subtitle{font-size:1.1em;opacity:.9;margin-bottom:15px}.header .meta{display:flex;gap:30px;font-size:.9em;opacity:.8;flex-wrap:wrap}.section{background:var(--white);border-radius:10px;padding:30px;margin-bottom:24px;box-shadow:0 1px 3px rgba(0,0,0,.08);border:1px solid var(--border)}.section h2{color:var(--primary);font-size:1.4em;margin-bottom:20px;padding-bottom:10px;border-bottom:2px solid var(--accent)}.section h3{color:var(--primary-light);margin:18px 0 10px;font-size:1.1em}table{width:100%;border-collapse:collapse;margin:15px 0;font-size:.95em}th{background:var(--primary);color:var(--white);padding:12px 15px;text-align:left;font-weight:600}td{padding:10px 15px;border-bottom:1px solid var(--border)}tr:nth-child(even){background:#f8fafc}tr:hover{background:#edf2f7}.callout{padding:16px 20px;border-radius:8px;margin:15px 0;border-left:4px solid}.callout-red{border-color:var(--red);background:var(--red-bg)}.callout-orange{border-color:var(--orange);background:var(--orange-bg)}.callout-green{border-color:var(--green);background:var(--green-bg)}.callout-blue{border-color:var(--blue);background:var(--blue-bg)}.callout strong{display:block;margin-bottom:4px}.question-card{background:var(--grey-bg);border:1px solid var(--border);border-radius:8px;padding:16px 20px;margin:12px 0}.question-card .question{font-weight:700;margin-bottom:6px}.question-card .rationale{font-style:italic;color:var(--text-light);font-size:.9em}.tag{display:inline-block;padding:3px 10px;border-radius:12px;font-size:.8em;font-weight:600;margin:2px}.tag-green{background:var(--tag-green);color:var(--tag-green-text)}.tag-red{background:var(--tag-red);color:var(--tag-red-text)}.tag-orange{background:var(--tag-orange);color:var(--tag-orange-text)}.grid-2{display:grid;grid-template-columns:1fr 1fr;gap:20px}.grid-3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px}.comp-card{background:var(--white);border:1px solid var(--border);border-radius:10px;padding:20px;border-top:3px solid var(--red)}.comp-card h4{color:var(--primary);margin-bottom:10px}.comp-card ul{list-style:none;padding:0}.comp-card li{padding:4px 0;font-size:.9em}.comp-card li::before{content:"- ";color:var(--red);font-weight:700}.hook-card{background:linear-gradient(135deg,#ebf8ff,#f0fff4);border:1px solid var(--border);border-radius:8px;padding:16px;margin:10px 0}.hook-card .label{font-weight:700;color:var(--accent);font-size:.85em;text-transform:uppercase;margin-bottom:6px}ul,ol{padding-left:24px}li{margin:4px 0}@media print{body{font-size:12px}.container{max-width:100%;padding:0}.section{box-shadow:none;break-inside:avoid}.header{background:var(--primary)!important;-webkit-print-color-adjust:exact;print-color-adjust:exact}}@media(max-width:768px){.grid-2,.grid-3{grid-template-columns:1fr}.header{padding:24px}}
</style>
</head>
<body>
<div class="container">
  <!-- Header: company name, subtitle with contact name & title, meta with event/date info -->
  <!-- Section 1: Contact Profile (grid-2 with table + career/skills, plus callout-blue for key context) -->
  <!-- Section 2: Company Overview (key facts table, core functions list, IT/OT environment table) -->
  <!-- Section 3: Critical News & Context (callout boxes: red=critical, orange=warning, green=positive, blue=info) -->
  <!-- Section 4: Discovery Questions (4 themes x 3 questions, each in question-card with .question and .rationale) -->
  <!-- Section 5: Versa Use Cases (grid-2 of callout-green boxes, 6-7 use cases) -->
  <!-- Section 6: Competitive Positioning (comparison table with .tag spans, then grid-3 of .comp-card weakness cards) -->
  <!-- Section 7: Meeting Strategy (hook-cards for openers, callout-blue for persona messages, question-cards for objections, ordered list for next steps) -->
  <!-- Section 8: Appendix — Industry Competitors table -->
  <!-- Footer: centered, muted text with "Prepared for Versa Networks" -->
</div>
</body>
</html>
```

### Key Structural Rules

- Wrap everything in `<div class="container">`
- Each section is `<div class="section">` with `<h2>` numbered headings
- Use `grid-2` for side-by-side layouts, `grid-3` for competitor weakness cards
- Callout severity: `callout-red` (security incidents, existential risks), `callout-orange` (financial pressure, deadlines, compliance gaps), `callout-green` (opportunities, strengths), `callout-blue` (context, background)
- Competitive tags: `tag-green` = Versa advantage, `tag-red` = competitor weakness, `tag-orange` = partial/neutral
- Footer: `"Prepared for Versa Networks • [DATE] • Confidential — For internal sales use only"`
- For existing Versa project folders, look at other `research.html` or `*.html` files in `~/projects/Versa/` as references for the exact format

## Example Trigger Phrases

- "Research Siemens for a meeting with Anna Müller, Head of Cybersecurity"
- "I'm meeting the CISO at HSBC, can you prepare me?"
- "Create prospect research for Maersk - contact is Lars Jensen, VP IT Infrastructure"
- "Research [company] for a sales call with [name]"
