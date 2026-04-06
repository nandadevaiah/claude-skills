---
description: Answer any question about Flowlyte's data pipeline architecture, compute engines, caching hierarchy, tiered scanning, math pipeline, or infrastructure.
---

# /flowlyte-dataarch-expert

## Purpose

Instantly answer questions about Flowlyte's data architecture using comprehensive domain knowledge. Covers the 6-layer cache hierarchy (L0-L5), math engine pipeline, tiered Cloud Run Jobs scanning, data source fallback chains, SC-54 snapshot injection, GCS integration, scheduling, API data flow, and known technical debt.

## Usage

```
/flowlyte-dataarch-expert [question]
```

Examples:
- `/flowlyte-dataarch-expert How does the cache hierarchy work?`
- `/flowlyte-dataarch-expert What is SC-54 snapshot injection?`
- `/flowlyte-dataarch-expert Explain the tiered scanning architecture`
- `/flowlyte-dataarch-expert What does process_pipeline() do step by step?`
- `/flowlyte-dataarch-expert How does the math engine compute FT_Score across timeframes?`
- `/flowlyte-dataarch-expert What are the known risks with the Cloud Run Jobs migration?`
- `/flowlyte-dataarch-expert What's the daily schedule timeline?`
- `/flowlyte-dataarch-expert How does merge_live_prices() work and what are its limitations?`
- `/flowlyte-dataarch-expert How do I add a new scanning tier?`

If question is omitted, ask the user what they want to know about.

## Workflow

1. **Load domain knowledge** — Read the skill file at `~/.claude/skills/flowlyte/DATAARCH.md` which contains the complete data architecture reference.

2. **Answer the question** using ONLY information from the skill file and the actual codebase. If the skill file covers the topic, answer directly. If the question requires checking current code state (e.g., "does this function still exist?"), read the relevant source files to verify.

3. **Include file paths and function names** in your answer so the user can navigate to the source code.

4. **If the question is about implementation details not covered in the skill file**, read the relevant source files:
   - Cache/pipeline: `backend/logic/aggregator.py`
   - Math engine: `backend/logic/math_worker.py`
   - GCS client: `backend/logic/ingestion/gcs_client.py`
   - Tier management: `backend/logic/tier_manager.py`
   - Scanner CLI: `backend/scan_runner.py`
   - API routes: `backend/api/main.py`
   - Background tasks: `backend/api/websocket_manager.py`
   - Pricing: `backend/logic/pricing_engine.py`
   - History: `backend/logic/historical.py`
   - Individual engines: `backend/logic/engines/*.py`

## Key Topics Covered

- **Cache Hierarchy**: L0 (raw GCS history), L1 (live scan cache), L2 (analytics JSON), L3 (processed stats - DISABLED), L4 (Gold Layer), L5 (Hive history)
- **Compute Paths**: 5-min market scan, live price updates, ticker tape WebSocket, post-market jobs, batch scripts
- **Math Engine**: `run_fast_scan()` → `process_pipeline()` → `run_math_task()` pipeline, all 26 engine modules
- **Data Sources**: Fallback chain (GCS history → vault → Polygon API), SC-54 snapshot injection
- **Tiered Scanning**: T1 (500 priority, 10min) + T2 (~1,596, 30min), shard/merge architecture
- **API Layer**: Which endpoints serve cached data, `merge_live_prices()` overlay
- **Scheduling**: Full daily timeline from 6:30 AM to 8:00 PM ET
- **Technical Debt**: 10 known issues with severity and mitigations
- **Infrastructure**: Cloud Run Jobs, Schedulers, `DISABLE_SCAN_SCHEDULERS` gate
