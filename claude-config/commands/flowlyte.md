---
description: Answer any question about Flowlyte domain concepts, metrics, architecture, user flows, or implementation details.
---

# /flowlyte

## Purpose

Instantly answer questions about the Flowlyte platform using comprehensive domain knowledge. Covers proprietary metrics (FT_Score, FVS, ETS, RS_Score, Squeeze), user workflows, AI agents, data pipeline, subscription tiers, and full architecture.

## Usage

```
/flowlyte [question]
```

Examples:
- `/flowlyte What is FVS_Z_Score and how is it calculated?`
- `/flowlyte How does the squeeze detection work?`
- `/flowlyte What's the data flow from scan to frontend display?`
- `/flowlyte Which features are PRO-only?`
- `/flowlyte How do I add a new metric to the screener?`
- `/flowlyte What agents exist in the AI system?`
- `/flowlyte Explain the top-down research workflow`

If question is omitted, ask the user what they want to know about.

## Workflow

1. **Load domain knowledge** — Read the skill file at `.claude/skills/flowlyte-domain-expert.md` which contains the complete domain reference.
2. **Answer the question** — Using the domain skill, provide a precise answer. Include:
   - Exact calculations/formulas when asking about metrics
   - File paths when asking about implementation
   - Thresholds and ranges when asking about scoring
   - Architecture diagrams (ASCII) when asking about system design
   - Step-by-step wiring instructions when asking how to add/modify features
3. **Verify against code** — If the answer involves specific files or functions, read the actual source to confirm the skill content is still accurate before responding. The skill is a snapshot; the code is the truth.

## Scope

This command covers:

### Proprietary Metrics
FT_Score, Trend_Strength, FVS (Val/Pct/Z_Score), RS_Score, ETS (Exponential Trend Strength), Squeeze Detection, A+ Setups, ATR Extension, Price Location, Sequencer, VW Keltner, BB_Width, Rel_Vol, Vol_ZScore, Sell_Vol_Pct, plus standard technicals (RSI, MACD, ADX, Supertrend, MFI, Stochastic)

### Pages & Features
Macro Economy, Market Breadth, Thematic Analysis (Monitor/Rotation/Discovery), Market Pulse, Screener, Squeeze Radar, Strategy Lab, Ticker Page, Option Corner, Portfolio, Trading Journal, Campaigns, Economic Calendar, Daily Briefing, Market Digest, AI Chat

### Architecture
Frontend (React/Vite, Context providers, React Query, API client), Backend (FastAPI, score engines, math worker, aggregator), AI Agents (LangGraph supervisor + 8 workers), Data Pipeline (3-tier cache, tiered scanning, parquet schema), Database (Supabase + RLS), Subscription Tiers

### Implementation Guidance
How to add new metrics, wire up new pages, extend the AI agent system, modify tier gating, update the scanner pipeline, add alert conditions

## Output

Concise, direct answers. For metric questions: include the formula, range, thresholds, and file location. For architecture questions: include the data flow and relevant files. For "how to" questions: include step-by-step instructions with file paths.
