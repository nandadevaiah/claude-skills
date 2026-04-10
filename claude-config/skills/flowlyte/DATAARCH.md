---
name: flowlyte-dataarch-expert
description: >
  Complete domain knowledge for Flowlyte's data pipeline architecture, compute engines,
  caching hierarchy, tiered scanning system, math engine pipeline, data source fallback chains,
  GCS integration, scheduling, theme discovery pipeline (dedup, PE enrichment, sector diversity),
  options data pipeline (snapshot runner, thematic heat, IV/ETS divergence, base-result caching,
  3-layer API cache, GCS live views, Cloud Run Jobs deployment), options flow persistence
  (WebSocket to GCS parquet + Supabase daily summaries + anomaly events), agent options
  intelligence pipeline (6 tools wired into Analyst/Guardian/Scout/Macro, options intelligence
  domain, Guardian proactive flow risk check, health engine option handling), and known
  technical debt.
version: 1.4.0
source: docs/architecture-data-pipeline.html
---

# Flowlyte Data Architecture Expert

Complete reference for the market intelligence platform data flow, compute paths, caching hierarchy, and engine architecture. Generated from the architecture-data-pipeline.html documentation (March 2026).

---

## 1. SYSTEM OVERVIEW

```
                         FLOWLYTE SYSTEM ARCHITECTURE

Browser (React/Vite)                         External APIs
      |                                         |
      | HTTP :3000 (dev)                        | Polygon.io, FMP, EODHD
      | proxied to :8002                        |
      v                                         v
+-------------------------------------------------+
|  Cloud Run Service (Single Docker Container)     |
|                                                 |
|  Gunicorn (2 workers, UvicornWorker)             |
|  +-------------------------------------------+  |
|  | FastAPI (backend/api/main.py)             |  |
|  |  - REST API endpoints                     |  |
|  |  - WebSocket (ticker tape, market score)  |  |
|  |  - CEO Graph (LangGraph AI agents)        |  |
|  +-------------------------------------------+  |
|  | Background Tasks (asyncio.create_task)     |  |
|  |  - schedule_market_update (5 min scan)    |  |
|  |  - schedule_pricing_update (5s DB write)  |  |
|  |  - broadcast_market_data (3s ticker tape) |  |
|  |  - schedule_theme_refresh (1h)            |  |
|  |  - schedule_fundamental_refresh (weekly)  |  |
|  |  - schedule_intelligence_feed (4x daily)  |  |
|  |  - schedule_deep_analysis_refresh (2x)    |  |
|  |  - schedule_options_flow_ws (persistent)  |  |
|  |  - schedule_scanner_refresh (tiered)      |  |
|  +-------------------------------------------+  |
+-------------------------------------------------+
      |                    |                  |
      v                    v                  v
Supabase          GCS Bucket         Local Disk
(PostgreSQL)      flowlyte-data-      backend/data/
- live_prices     lake-v1             - cache/
- assets          - ticks/            - vault/
- profiles        - cache/            - history/
- tickers         - gold/
- market_intel    - processed/
- watchlists      - options/
```

### Components

- **Frontend**: React 19 + TypeScript + Vite. Port 3000 (dev). Proxied `/api` and `/ws` to backend. Built into `/app/backend/static` in Docker.
- **Backend**: FastAPI v0.28.3, Python 3.12. Served via Gunicorn (2 UvicornWorkers). Port 8000 in Docker (mapped to 8002 locally). Timeout: 300s.
- **Database**: Supabase PostgreSQL with Row Level Security. Backend uses `SUPABASE_SERVICE_ROLE_KEY` to bypass RLS. Frontend uses anon key + session tokens.

### Deployment (Dockerfile Multi-Stage)

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| 1. frontend-build | node:20-alpine | Build React app (Vite). Inlines `VITE_*` env vars at build time. |
| 2. backend | python:3.12-slim-bookworm | Install pip deps, copy backend + execution scripts, copy React dist to `/app/backend/static`. |

**Entrypoint**: `start_gunicorn.sh` — runs `gunicorn api.main:app` with `--workers $WORKERS --worker-class uvicorn.workers.UvicornWorker --preload --timeout 300`. Default: 2 workers (clamped by `MAX_WORKERS` env var to prevent OOM on Cloud Run).

**WORKDIR** is `/app/backend`, so imports reference `api.main:app` (not `backend.api.main:app`). `PYTHONPATH` is set to `/app`.

---

## 2. CACHE HIERARCHY (6 Layers)

```
CACHE HIERARCHY (checked in order for reads)

L1 Local Parquet  ──>  L1 GCS Live Cache  ──>  L4 Gold Layer
backend/data/          gs://bucket/            gs://bucket/
cache/{date}.parquet   cache/{date}.parquet    gold/{date}.parquet
(written by scanner)   (synced on save)        (immutable archive)

L2 Analytics JSON     L3 Processed Stats    L5 Hive History
backend/data/cache/    gs://bucket/            backend/data/history/
analytics_{date}.json  processed/{tkr}/        Ticker={TKR}/data.parquet
(dashboard rollup)     metrics.parquet         (365-day per-ticker)
                       *** DISABLED ***

L0 Raw Ticker History                         Local Vault
gs://bucket/ticks/                              backend/data/vault/
{TICKER}/daily.parquet                          interval=D/ticker=AAPL/
(20-year OHLCV archive)                         (auto-populated from API)
```

### L0 — Raw Ticker History

- **GCS Path**: `gs://flowlyte-data-lake-v1/ticks/{TICKER}/daily.parquet`
- **Who writes**: `scripts/ingest_all_parallel.py` (SuperIngestor) — bulk 20-year history from Polygon. Also `gcs.sync_ticker_histories()` at 4:20 PM ET daily.
- **Who reads**: `gcs_client.get_ticker_history()` called by `process_pipeline()` in `aggregator.py` during scans.
- **Local cache**: `backend/cache/market_data/{TICKER}_daily.parquet` — L0 local cache with no TTL (history is static enough for a scan session).
- **Timeframes**: `daily.parquet`, `hourly.parquet`, `m30.parquet`
- **Size**: ~2,000 tickers x 5,000 rows (20yr daily) = ~10M rows total
- **Key files**: `backend/logic/ingestion/gcs_client.py` (`get_ticker_history()`, `upload_ticker_history()`, `sync_ticker_histories()`), `scripts/ingest_all_parallel.py` (`SuperIngestor.process_ticker()`)

### L1 — Live Scan Cache

- **Local**: `backend/data/cache/{date}.parquet`
- **GCS**: `gs://bucket/cache/{date}.parquet`
- **Who writes (local)**: `save_cache()` in `aggregator.py`, called by `scan_runner.py` after `run_fast_scan()`.
- **Who writes (GCS)**: `gcs.upload_cache()` called inside `save_cache()` — auto-sync on every save.
- **Who reads**: `load_cache()` in `aggregator.py`. Used by `/api/market/scan`, `/api/dashboard/summary`, market score calculation.
- **Staleness check**: 60 seconds (`max_age_seconds=60`). If local file is older for today/yesterday, `_refresh_from_gcs()` downloads a fresher version.
- **Fallback chain**: Local L1 → GCS Live Cache → Gold Layer (L4)
- **Schema**: ~2,000 rows x ~120+ columns (Ticker, FT_Score, Trend_Strength, RS_Score, all VW Keltner, Z-Scores, fundamentals, etc.)
- **GCS FUSE**: If `backend/data/gcs/` directory exists (Cloud Run FUSE mount), `CACHE_DIR` switches to `backend/data/gcs/cache/`.
- **Key files**: `backend/logic/aggregator.py` (`load_cache()`, `save_cache()`, `_is_local_cache_stale()`, `_refresh_from_gcs()`), `backend/scan_runner.py`

### L2 — Analytics JSON

- **Path**: `backend/data/cache/analytics_{date}.json`
- **Who writes**: `precompute_dashboard_analytics()` in `aggregator.py` — triggered by `save_cache()` on every scan save.
- **Who reads**: `/api/dashboard/summary` endpoint. Freshness check: JSON mtime >= parquet mtime.
- **Contents**: Breadth (bulls/bears/total/ratio), core metrics (MKT SCORE, INDICES, B10, SECTORS), sections (indices, commodities, currencies, debt, global, sectors, top movers, watchlists).
- **GCS sync**: Uploaded to GCS via `upload_analytics()`, downloaded by `_refresh_from_gcs()` alongside the parquet.

### L3 — Processed Stats (DISABLED / CORRUPTED)

- **GCS Path**: `gs://flowlyte-data-lake-v1/processed/{TICKER}/metrics.parquet`
- **Who writes**: `backend/scripts/generate_processed_layer.py` — `ProcessedLayerGenerator`.
- **Who reads**: `gcs_client.get_processed_stats()` — **CURRENTLY DISABLED** in `process_pipeline()`.
- **Why disabled**: Processed stats are pre-computed snapshots that bypass live price injection (SC-54). They contain stale/corrupted prices (NaT rows). Fast path removed to force all tickers through the full pipeline.
- **Status**: **CORRUPTED — do not use until regenerated with NaT fix.**

### L4 — Gold Layer

- **GCS Path**: `gs://flowlyte-data-lake-v1/gold/{date}.parquet`
- **Who writes (daily)**: `gcs.promote_to_gold(date_str)` — copies `cache/{date}.parquet` to `gold/{date}.parquet` in GCS. Now auto-promoted after every `merge_tier_shards()`.
- **Who writes (backfill)**: `backend/scripts/generate_gold_layer.py` — `GoldLayerGenerator`. Uses multiprocessing for speed.
- **Who reads**: `load_cache()` Gold Layer fallback: if no local L1 and no GCS live cache, tries `gcs.get_gold_cache(date_str)`.
- **Nature**: Immutable historical archive. Same schema as L1 cache. One file per trading day.
- **Local cache**: `backend/cache/gold/{date}.parquet` — no TTL since immutable.

### L5 — Hive-Partitioned History

- **Path**: `backend/data/history/Ticker={TICKER}/data.parquet`
- **Who writes**: `consolidate_history(365)` in `backend/logic/historical.py`. Scans last 365 days of L1 cache files, merges into per-ticker Hive partitions.
- **When**: 4:10 PM ET daily via `run_consolidation()` in `scheduler.py`.
- **Who reads**: `/api/market/history/{ticker}` endpoint via `historical.get_stock_history()`. Read-through: L5 local → GCS raw history → write back to L5.
- **Columns (subset)**: Ticker, Date, Trend_Strength, FT_Score, RS_Score, Rel_Vol, Close, OHLCV, VW Keltner (7 cols), FVS (6 cols), ETS Badge, Squeeze, A_Plus_Setup.
- **Lock**: `backend/data/history_write.lock` — prevents concurrent writes during wipe+rebuild.

### Live Prices (Supabase Table)

- **Table**: `live_prices` (joined with `assets`)
- **Who writes**: `PricingEngine.update_all_prices()` in `backend/logic/pricing_engine.py`. Fetches from Polygon Snapshot API, upserts to `live_prices`.
- **Frequency**: Every 5 seconds via `schedule_pricing_update()` background task.
- **Who reads**: `merge_live_prices()` in `main.py`. Called by `/api/market/scan` (today only) and `/api/dashboard/summary`.
- **What it updates**: Only `Price` and `Close` fields. Does **NOT** update Change, OHLCV, or any computed indicators.
- **Asset types**: EQUITY (delta=1.0) and OPTION (with Greeks: delta, gamma, theta, vega, IV). BSM fallback for illiquid options.

---

## 3. COMPUTE PATHS

All compute currently runs on the same Cloud Run Service container that serves the API. Heavy compute is being offloaded to Cloud Run Jobs (see Section 9).

### A. 5-Minute Market Scan (Heaviest Workload)

```
schedule_market_update() → scan_market() → subprocess: scan_runner.py → run_fast_scan()

run_fast_scan() → process_pipeline() x ~2000 → run_math_task() (ProcessPool) → save_cache() + GCS sync
```

| Step | Location | Detail |
|------|----------|--------|
| 1. Trigger | `websocket_manager.py` | `schedule_market_update()` — asyncio background task, runs every 300s during market hours. Uses `market_update.lock`. |
| 2. Orchestrate | `aggregator.py` | `scan_market()` — loads existing cache, identifies missing tickers, writes ticker list to temp JSON, spawns subprocess. |
| 3. Subprocess | `scan_runner.py` | Launched via `subprocess.run()` from `scan_market`. Calls `run_fast_scan()` async. Merges results into existing cache with file lock. |
| 4. Data Fetch | `aggregator.py` | `process_pipeline()` per ticker: GCS raw history → date slice → SC-54 snapshot injection. Semaphore-limited (default 50 concurrent). |
| 5. Math | `math_worker.py` | `run_math_task()` via `ProcessPoolExecutor` (4 workers). CPU-intensive: FT_Score, RS_Score, VW Keltner, ETS, VWAP, Z-Scores, sequencer, volume across 10 timeframes. 60s timeout per ticker. |
| 6. Save | `aggregator.py` | `save_cache()` writes parquet, syncs to GCS, triggers L2 precompute, fires batch event detection. |

**Performance Config**: Workers: 4, Semaphore: 50, TCP Limit: 500, Timeout: 60s/ticker

**Env Overrides**: `MAX_WORKERS=4`, `API_CONCURRENCY=50`, `OMP_NUM_THREADS=1`

**Problem**: This scan can take >5 minutes for ~2,000 tickers, causing skipped 5-minute cycles. It runs on the same container as the API, competing for CPU/memory with request handling, ticker tape, pricing engine, and AI agents.

### B. Live Price Updates

```
schedule_pricing_update() → PricingEngine.update_all_prices() → Polygon Snapshot API → Supabase live_prices upsert
```

- **Trigger**: `schedule_pricing_update()` in `websocket_manager.py`. Every 5 seconds. Lock: `pricing_engine.lock`.
- **Process**: Fetches all assets from `assets` table. Groups into equities and options. Equities: batch snapshot (`/v2/snapshot/...`). Options: per-underlying snapshot (`/v3/snapshot`). BSM fallback for illiquid options.
- **Output**: Upserts to `live_prices` table (chunks of 500). Fields: price, delta, gamma, theta, vega, iv, pricing_source, updated_at.

### C. Ticker Tape WebSocket

```
broadcast_market_data() → fetch_prices() → Apply jitter to LAST_PRICES → WebSocket broadcast
```

- **Interval**: Every 3 seconds (`UPDATE_INTERVAL = 3.0`)
- **Base prices**: Fetched from Polygon daily aggregates (7-day lookback) at startup via `init_base_prices()`. Cached to `backend/data/cache/base_prices_v2.json`. Refreshed every 60s during market hours.
- **Jitter**: During market hours: +/-0.01% price jitter, +/-0.001% change jitter. Market closed: static.
- **Payload**: JSON: `{type: "ticker_update", market_score: {...}, data: [{symbol, price, change, up, timestamp}]}`
- **Tickers**: 38 fixed tickers: US indices (SPY, QQQ, IWM, DIA, RSP), Mega caps (10), Commodities (2), Bonds/Currency (4), Global (9), Crypto (2), Forex (2).

> **Important**: The ticker tape shows simulated prices (base price + micro-jitter), NOT real-time live prices. The `refresh_base_prices_loop()` updates from Polygon every 60 seconds, but individual broadcasts add cosmetic jitter only.

### D. Post-Market Jobs (scheduler.py)

Execution model: `backend/scheduler.py` is a standalone infinite-loop process (separate from the FastAPI app). It checks time windows and spawns subprocesses for each job.

| Time (ET) | Job | Function | Subprocess Command | Timeout |
|-----------|-----|----------|-------------------|---------|
| 4:10-4:15 PM | L3/L5 Consolidation | `run_consolidation()` | `backend.logic.historical.consolidate_history(365)` | 900s |
| 4:20-4:25 PM | GCS History Sync | `run_gcs_history_sync()` | `gcs.sync_ticker_histories(ALL_TICKERS, 'daily')` | 1800s |
| 4:25-4:30 PM | Gold Promotion | `run_gold_promotion()` | `gcs.promote_to_gold(date_str)` | 120s |
| 4:30-4:35 PM | Daily Briefing | `run_daily_briefing()` | `backend.logic.daily_briefing.generate_bulk_briefings()` | 1800s |
| 8:00-8:05 AM | Pre-market Briefing | `run_daily_briefing()` | Same as above | 1800s |

> **Note**: During market hours (9:30 AM - 4:00 PM ET), `scheduler.py` runs `run_scan()` every 5 minutes via subprocess (`scan_runner.py --date today --tickers all --incremental`). This is the same `scan_runner` used by the app server's `schedule_market_update()` background task, creating potential double-scanning if both are running.

### E. Nightly/Manual Batch Jobs

| Script | Purpose | Data Flow |
|--------|---------|-----------|
| `scripts/ingest_all_parallel.py` | Full 20-year history ingest | Supabase tickers → Polygon daily candles → math_worker → GCS `ticks/{TICKER}/daily.parquet` |
| `backend/scripts/generate_processed_layer.py` | Pre-compute per-ticker metrics | GCS raw history → math_worker → GCS `processed/{TICKER}/metrics.parquet` |
| `backend/scripts/generate_gold_layer.py` | Backfill Gold Layer for date range | GCS raw history → multiprocessing math_worker per date → GCS `gold/{DATE}.parquet` |

### App Server Background Tasks (websocket_manager.py)

| Task | Interval | Description |
|------|----------|-------------|
| `broadcast_market_data()` | 3s | Ticker tape + market score to all WS clients |
| `refresh_base_prices_loop()` | 60s | Re-fetch Polygon aggregates for ticker tape base prices |
| `schedule_market_update()` | 300s | 5-min full market scan (heaviest task) |
| `schedule_pricing_update()` | 5s | Real-time pricing to `live_prices` DB |
| `schedule_theme_refresh()` | 3600s | Refresh global theme cache |
| `schedule_fundamental_refresh()` | Weekly (Sat 23:00 UTC) | Full fundamental data fetch for all tickers |
| `schedule_deep_analysis_refresh()` | 2x daily (8:30, 12:30 ET) | FMP analysis + options for priority tickers |
| `schedule_intelligence_feed()` | 4x daily (6:30, 10:30, 13:00, 16:30 ET) | AI intelligence feed generation |
| `schedule_options_flow_ws()` | Persistent | Polygon options flow WebSocket connection |
| `schedule_scanner_refresh()` | 5/15/30 min tiered | Tiered scanner: top 30 every 5m, next 30 every 15m |
| `GlobalCacheWarmer.warm_cache()` | Startup | Smart L3 cache warming |

---

## 4. MATH ENGINE PIPELINE

```
run_fast_scan(tickers, target_date)                    [aggregator.py:561]
  |
  +-- Fetch SPY benchmark (300 days incremental / 1500 full)
  +-- Load ticker details cache
  +-- SC-54: Fetch Polygon snapshots for all tickers (if today)
  +-- Create ProcessPoolExecutor (4 workers)
  +-- Create asyncio.Semaphore (50 concurrent)
  |
  +-- For each ticker (asyncio.gather):
      |
      process_pipeline(ticker, target_date, snapshot)       [aggregator.py:365]
        |
        +-- GCS processed stats: DISABLED
        +-- GCS raw ticker history -> date-slice to target_date
        +-- Local vault fallback
        +-- Polygon API fetch (last resort)
        +-- SC-54 Snapshot Injection:
        |     If today: overlay Polygon real-time OHLCV onto last row
        |     - Append new row if last date < today
        |     - Update existing row if last date == today
        +-- Auto-populate vault from API fetch
        |
        +-- run_math_task(ticker, details, daily, hourly, m30, m15, benchmark)
              [math_worker.py:102 -- runs in ProcessPoolExecutor]
              |
              +-- Data validation (min 20 bars, staleness check)
              +-- Clean & standardize (float32, ffill, fillna)
              +-- Engine calculations:
              |     trend.calc_rs_score(daily, benchmark)
              |     volatility.calc_atr_extension(daily)
              |     volume.calc_volume_metrics(daily)
              |     volume.calc_fvs(daily)
              |     ets_engine.calc_exponential_trend_strength(daily, benchmark)
              |     vwap_engine.calculate_mtf_vwap(daily)
              |     sequencer.calculate_sequencer_timeseries(daily)
              |
              +-- Multi-timeframe scoring (10 TFs):
              |     W, 4D, 3D, 2D, D, 4h, 2h, 1h, 30m, 15m
              |     Each: calculate_ft_score() + _calc_vw_metrics()
              |     Daily resampled to W/4D/3D/2D
              |     Hourly resampled to 2h/4h
              |
              +-- Z-Scores: 8 windows (5,10,20,30,60,90,126,252)
              +-- Aggregate: FT_Score = sum(scores), Trend_Strength = %
              +-- Build output row (~120+ fields)
```

### Engine Modules

| Module | Path | Key Function |
|--------|------|-------------|
| Trend/RS | `backend/logic/engines/trend.py` | `calc_rs_score(daily, benchmark)` — Relative Strength vs SPY |
| Volatility | `backend/logic/engines/volatility.py` | `calc_atr_extension(daily)` — ATR extension from mean |
| Volume | `backend/logic/engines/volume.py` | `calc_volume_metrics(daily)`, `calc_fvs(daily)` — Rel Vol, FVS |
| ETS | `backend/logic/engines/ets_engine.py` | `calc_exponential_trend_strength(daily, benchmark)` |
| VWAP | `backend/logic/vwap_engine.py` | `calculate_mtf_vwap(daily)` — Multi-timeframe VWAP |
| Sequencer | `backend/logic/sequencer.py` | `calculate_sequencer_timeseries(daily)` |
| VW Keltner | `backend/logic/vw_keltner.py` | `calculate_vw_keltner(df, length, factor)` |
| Score | `backend/logic/score_engine.py` | `calculate_ft_score(df)` — returns (score, squeeze, signal, extras) |

### All 26 Engine Files in `backend/logic/engines/`

| File | Description |
|------|-------------|
| `trend.py` | RS Score, relative strength calculations |
| `volatility.py` | ATR extension, volatility metrics |
| `volume.py` | Volume metrics, FVS (Flowlyte Volume Spread) |
| `ets_engine.py` | Exponential Trend Strength composite |
| `momentum_engine.py` | Momentum-based technical analysis |
| `theme_engine.py` | Dynamic theme scoring from DB |
| `options_flow_engine.py` | Options flow data processing |
| `options_flow_ws.py` | Persistent Polygon options WebSocket |
| `options_scanner_engine.py` | Options screening engine |
| `macro_engine.py` | Macro economic analysis |
| `sentinel_engine.py` | Market intelligence signal detection |
| `guardian_engine.py` | Portfolio guardian/monitoring |
| `health_engine.py` | Investment health scoring |
| `allocation_monitor.py` | Portfolio allocation monitoring |
| `positioning_engine.py` | Market positioning analysis |
| `hype_engine.py` | Social/hype scoring |
| `smc.py` | Smart Money Concepts |
| `smc_gex_confluence.py` | SMC + GEX confluence analysis |
| `correlation.py` | Cross-asset correlation |
| `flow_anomaly_detector.py` | Options flow anomaly detection |
| `flow_persistence.py` | Persistent flow tracking |
| `iv_ets_divergence.py` | IV vs ETS divergence signals |
| `thematic_options_heat.py` | Theme-level options heatmap |
| `batch_event_detector.py` | Post-scan batch event detection |
| `scanner_scheduler.py` | Tiered scanner scheduling |

---

## 5. DATA SOURCE HIERARCHY IN process_pipeline()

When `process_pipeline()` needs daily OHLCV for a ticker, it follows this fallback chain:

| Priority | Source | Status | Detail |
|----------|--------|--------|--------|
| 1 (DISABLED) | GCS Processed Stats | DISABLED | Was `gcs.get_processed_stats(ticker)`. Returned stale pre-computed metrics that bypassed SC-54 live injection. Corrupted with NaT data. |
| 2 | GCS Raw Ticker History | ACTIVE | `gcs.get_ticker_history(ticker)`. Date-sliced to `target_date + 1 day`. Local L0 cache at `backend/cache/market_data/`. |
| 3 | Local Vault | ACTIVE | `vault_manager.get_from_vault(ticker, "D")`. Hive-partitioned at `backend/data/vault/interval=D/ticker={TKR}/`. |
| 4 | Polygon API (live fetch) | ACTIVE | `async_fetch_daily(session, ticker, limit_days=5500)`. Last resort. Auto-populates vault after successful fetch. |

### SC-54 Snapshot Injection

When scanning today's date, `run_fast_scan()` pre-fetches Polygon real-time snapshots for all tickers via `PolygonWrapper.get_stock_snapshots()` (batched in chunks of 50). These snapshots are passed to `process_pipeline()` which overlays them onto the daily DataFrame:

- If daily_df's last date < today: appends a new row with snapshot's OHLCV
- If daily_df's last date == today: updates the existing last row with snapshot's close, high, low, volume
- Priority: `day.c` (Polygon day candle close) → `lastTrade.p` (last trade price) → existing close

This ensures `math_worker` operates on real-time data, not yesterday's close.

---

## 6. API ENDPOINTS THAT SERVE CACHED DATA

| Endpoint | Method | Data Source | Live Overlay |
|----------|--------|-------------|--------------|
| `/api/market/scan` | GET | `load_cache(date)` → fallback to latest available date | Yes (today only) — `merge_live_prices(records)` updates Price/Close from `live_prices` DB table |
| `/api/dashboard/summary` | GET | L2 analytics JSON (if fresh) → recompute from L1 parquet → `merge_live_prices()` | Yes — recursively merges into nested sections (indices, sectors, movers, watchlists) |
| `/api/market/history/{ticker}` | GET | L5 Hive partition → GCS raw history fallback → write-back to L5 | No |
| `/api/market/scan/trigger` | GET | Triggers a scan subprocess, returns when done | N/A (produces data, does not serve it) |
| WebSocket `/ws` | WS | Ticker tape: `LAST_PRICES` dict (Polygon base prices + jitter). Market score: FT_Score avg from parquet cache. | No — simulated jitter only |

> **`merge_live_prices()` limitation**: Only updates Price and Close fields. Does NOT update Change, Open, High, Low, Volume, or any computed indicators (FT_Score, Trend_Strength, etc.). This means the dashboard shows live prices but stale indicators until the next scan cycle completes.

---

## 7. DAILY SCHEDULE TIMELINE

All times are US Eastern (ET). Weekdays only.

| Time | Event | Description |
|------|-------|-------------|
| 6:30 AM | Intelligence | Pre-market intelligence feed generation (full run). AI-generated market signals and analysis. |
| 8:00 AM | Briefing | Pre-market daily briefing generation for all active users. Runs via `scheduler.py` subprocess. |
| 8:30 AM | Analysis | Deep analysis refresh: FMP Investment Health + Polygon Options Pulse for priority tickers (Big 10 + key sectors + watchlists). |
| 9:30 AM | **MARKET OPEN** | All high-frequency tasks activate: 5-min scan (~2,000 tickers), 5s pricing (Polygon → `live_prices`), 3s ticker tape (jittered to WS), 60s base refresh, tiered scanner (top 30 every 5m, next 30 every 15m). |
| 10:30 AM | Intelligence | Mid-morning intelligence feed refresh (intraday signals). |
| 12:30 PM | Analysis | Mid-day deep analysis refresh. |
| 1:00 PM | Intelligence | Midday intelligence feed update. |
| 4:00 PM | **MARKET CLOSE** | 5-min scans stop. Pricing engine continues (extended hours until 8 PM). Ticker tape goes static. |
| 4:10 PM | L5 Consolidation | `consolidate_history(365)` — Merges 365 days of cache parquets into per-ticker Hive partitions. Timeout: 15 min. |
| 4:20 PM | GCS History Sync | `gcs.sync_ticker_histories(ALL_TICKERS, 'daily')` — Uploads local vault OHLCV to GCS ticks/. Timeout: 30 min. |
| 4:25 PM | Gold Promotion | `gcs.promote_to_gold(date)` — Copies `cache/{date}.parquet` to `gold/{date}.parquet` in GCS. Immutable archive. Timeout: 2 min. |
| 4:30 PM | Briefing + Intelligence | Post-close daily briefing + post-close intelligence feed summary. |
| 8:00 PM | End | Extended hours end. Pricing engine pauses. All background tasks idle until next morning. |
| Sat 23:00 UTC | Weekly | Weekly fundamental data refresh: full scan with `fetch_fundamentals=True` (EODHD/Polygon fundamentals for all tickers). |

---

## 8. KNOWN ISSUES / TECHNICAL DEBT

1. **All heavy compute on app server**: The 5-minute market scan (`ProcessPoolExecutor` with 4 workers processing ~2,000 tickers) runs on the same Cloud Run container that serves HTTP/WebSocket requests. CPU spikes during scans degrade API response times.

2. **GCS NaT row corruption**: Raw ticker history in GCS contains rows with NaT (Not a Time) timestamps. These corrupt the date-slicing logic in `process_pipeline()` and caused the processed stats layer to become unreliable. **Fix applied**: `df = df[df.index.notna()]` at three defense layers.

3. **Processed stats layer corrupted**: L3 (`gs://bucket/processed/{ticker}/metrics.parquet`) contains stale/corrupted data. The fast path in `process_pipeline()` has been disabled. Needs full regeneration with NaT fix applied.

4. **Ticker tape shows simulated prices**: `fetch_prices()` applies +/-0.01% jitter to base prices fetched from Polygon daily aggregates. This is cosmetic animation, not real-time data. Base prices refresh every 60s.

5. **merge_live_prices only updates Price/Close**: The live overlay does NOT update Change%, OHLCV, or any computed indicators. Users see live prices but stale FT_Score/Trend_Strength until the next 5-minute scan completes.

6. **Scanner can take >5 min**: With ~2,000 tickers and 10 timeframes, the full scan can exceed the 5-minute cycle. This causes skipped cycles and increasingly stale data during volatile markets.

7. **Potential double-scanning**: Both `scheduler.py` (standalone process) and `schedule_market_update()` (app server background task) trigger scans during market hours. If both run, they compete for Polygon API rate limits and file locks.

8. **Duplicate startup events**: `main.py` had two `@app.on_event("startup")` handlers. **Fix applied**: Consolidated into a single startup handler.

---

## 9. TIERED CLOUD RUN JOBS ARCHITECTURE (Implemented March 28, 2026)

```
              IMPLEMENTED: TIERED SPLIT COMPUTE ARCHITECTURE

Browser                                    Cloud Schedulers
  |                                            |
  v                                            |  flowlyt-tier-refresh-schedule
Cloud Run Service                             |    cron: 25 9 * * 1-5 ET (daily pre-market)
(API-only, no heavy compute)                |
+-----------------------------+             |  flowlyt-scanner-t1-schedule
| FastAPI                     |             |    cron: */10 9-16 * * 1-5 ET
| - Serve cached data         |             |
| - merge_live_prices overlay |             |  flowlyt-scanner-t2-schedule
| - WebSocket ticker tape     |             |    cron: */30 9-20 * * 1-5 ET
| - AI agents (LangGraph)     |             |
| - Pricing engine (5s)       |             v
+-----------------------------+    Cloud Run JOBs
         |                         +--------------------------------+
         |                         | flowlyt-tier-refresh           |
         |                         |   tier_manager.py --date today |
         |                         |   Auto-assign 500 T1 by mktcap|
         |                         |   2 vCPU / 1 GB, ~3 min       |
         |                         +--------------------------------+
         |                         +--------------------------------+
         |                         | flowlyt-scanner-t1 (Priority)  |
         |                         |   500 tickers, every 10 min    |
         |                         |   4 vCPU / 4 GB, ~9 min       |
         |                         +--------------------------------+
         |                         +--------------------------------+
         |                         | flowlyt-scanner-t2 (Remainder) |
         |                         |   ~1,596 tickers, every 30 min |
         |                         |   2 vCPU / 2 GB, ~20 min      |
         |                         +--------------------------------+
         |                                       |
         v                                       v
         +-------> read cache/ <---------  GCS Bucket (shared data layer)
                                           gs://flowlyte-data-lake-v1/
                                             cache/tiers/{date}/t1.parquet
                                             cache/tiers/{date}/t2.parquet
                                             cache/tiers/{date}/manifest.json
                                             cache/{date}.parquet  (merged)
                                             gold/{date}.parquet   (auto-promoted)
```

### Before vs After

| Before | After | Benefit |
|--------|-------|---------|
| Single scanner job, all 2,096 tickers every 15 min | T1 (500 priority) every 10 min + T2 (1,596 remainder) every 30 min | 5x faster refresh for top tickers; ~$53/mo vs ~$59/mo single job |
| Single GCS cache file (write conflicts) | Tier-specific shards merged into unified file | No race conditions; concurrent jobs safe; scales to T3/T4 |
| Static ticker list | Auto-assigned by market cap daily (`tier_manager.py`) | Priority list stays current without manual maintenance |
| Gold promotion in scheduler.py (paused) | Auto-promoted after every merge in `merge_tier_shards()` | Gold layer always up to date; no separate job needed |
| Local dev/staging can't access production data | GCS client with project ID fallback; all environments pull from GCS | Dev/staging always have fresh data without running scanners |

### Tier Data Flow

1. **9:25 AM ET** — `flowlyt-tier-refresh` computes tier assignment from `ticker_details.parquet` market cap data. Uploads manifest to `cache/tiers/{date}/manifest.json`.
2. **9:30+ AM ET** — T1 reads manifest, scans 500 tickers, writes `cache/tiers/{date}/t1.parquet`, merges all shards → `cache/{date}.parquet`, promotes to gold.
3. **9:30+ AM ET** — T2 reads manifest, scans ~1,596 tickers, writes `cache/tiers/{date}/t2.parquet`, merges all shards → `cache/{date}.parquet`, promotes to gold.
4. **API server** — `load_cache()` reads unified `cache/{date}.parquet` from GCS (60s staleness check). Zero changes to API endpoints.

### Concurrency Safety

T1 and T2 write to separate GCS paths (no conflict). Both call `merge_tier_shards()` which reads all shards and produces the same merged output. GCS atomic writes mean last writer wins — identical result regardless of order.

### Scaling to 5,000+ Tickers

1. Add tier to `TIER_CONFIG` in `tier_manager.py` (e.g., `"t3": {"name": "Extended", "max_tickers": 1500}`)
2. Create one Cloud Run Job + Scheduler for the new tier
3. `merge_tier_shards()` discovers shards dynamically via `list_tier_shards()` — no code changes needed
4. `load_cache()` reads the merged file unchanged — no API changes needed

### Cloud Run Jobs & Schedulers

| Job | Schedule | Resources | Timeout |
|-----|----------|-----------|---------|
| `flowlyt-scanner-t1` | `*/10 9-16 * * 1-5 ET` | 4 vCPU / 4 GB | 600s |
| `flowlyt-scanner-t2` | `*/30 9-20 * * 1-5 ET` | 2 vCPU / 2 GB | 1800s |
| `flowlyt-tier-refresh` | `25 9 * * 1-5 ET` | 2 vCPU / 1 GB | 300s |
| `flowlyt-scanner` (legacy) | PAUSED | 4 vCPU / 4 GB | 900s |

Estimated monthly cost: ~$53/mo (T1 ~$40 + T2 ~$12 + Refresh ~$1)

### DISABLE_SCAN_SCHEDULERS Env Var

Set `DISABLE_SCAN_SCHEDULERS=true` on the Cloud Run Service to disable `schedule_market_update()` and `schedule_fundamental_refresh()` on the app server. All lightweight tasks (ticker tape, live_prices, themes, intelligence, options flow) always run. Instant rollback: remove the env var.

---

## 10. RE-ARCHITECTURE RECOMMENDATION: FULL CLOUD RUN JOBS

### Target Architecture

```
                   Cloud Scheduler (cron)
                        |
          +-------------+-------------+
          |             |             |
  [Job: market-scan] [Job: post-close] [Job: deep-analysis]
   Every 5 min (MH)   4:10 PM ET      8:30 AM, 12:30 PM
          |             |             |
          v             v             v
       GCS (cache/{date}.parquet, gold/{date}.parquet)
          ^
          |  load_cache() reads from GCS (already implemented)
          |
  [Cloud Run Service: flowlyte-api]
   - FastAPI API endpoints
   - WebSocket broadcast (ticker tape)
   - live_prices update (5s)
   - Theme refresh (hourly, lightweight)
   - Options flow WS (persistent)
```

### What Stays on App Server

| Task | Why It Stays |
|------|-------------|
| API request handling | Core function — serves cached data, no compute |
| `broadcast_market_data()` | 3-second WebSocket loop, reads cached data, lightweight |
| `schedule_pricing_update()` | 5-second Polygon snapshot to `live_prices` — I/O only, no CPU |
| `schedule_theme_refresh()` | Hourly, lightweight DB/cache writes |
| `schedule_options_flow_ws()` | Persistent WebSocket, event-driven, low CPU |

**Resource Impact**: Before: 2 vCPU, 2-4 GiB → After: 1 vCPU, 1 GiB (~50% cost reduction).

---

## 11. RISKS & MITIGATIONS

| # | Risk | Severity | Root Cause | Mitigation |
|---|------|----------|-----------|------------|
| 1 | File lock incompatibility | CRITICAL | `SimpleFileLock` uses local OS filesystem | Disable app-server scan BEFORE enabling Job |
| 2 | Concurrent GCS writes | HIGH | No atomic write pattern on GCS upload | Only one writer post-cutover; staging blob long-term |
| 3 | Concurrent local parquet writes | HIGH | Direct `to_parquet()` with no temp file | Post-cutover: Job writes, service only reads GCS |
| 4 | Analytics JSON not generated | MEDIUM | `precompute_dashboard_analytics()` can fail silently | Existing slow fallback handles it; GCS sync added |
| 5 | Cache staleness window (up to 10 min) | MEDIUM | 5-min GCS interval + staleness check | Reduced `max_age_seconds` from 300 to 60 |
| 6 | Scan subprocess no timeout | MEDIUM | `subprocess.Popen()` with no timeout | Cloud Run Job has built-in `--task-timeout 600` |
| 7 | Missing env vars in Cloud Run Job | MEDIUM | `load_dotenv()` expects .env file on disk | Configure all vars via Secret Manager |
| 8 | GCS FUSE not mounted in Job | MEDIUM | `CACHE_DIR` falls back to ephemeral local path | Acceptable: writes local then uploads to GCS |
| 9 | 5-min Cloud Scheduler overlap | MEDIUM | Job takes >5 min, next trigger fires | Set `--max-instances 1` on the Cloud Run Job |
| 10 | Dashboard slow fallback | LOW | On-the-fly analytics generation is 2-5s | Existing behavior, not a regression |

**Key Takeaway**: Most risks are self-mitigating because the app-server scan is disabled before the Cloud Run Job becomes the sole writer. During the parallel observation phase, both writers produce identical output, so GCS last-writer-wins is safe.

---

## 12. FILE REFERENCE INDEX

### Core Pipeline

| File | Key Functions |
|------|--------------|
| `backend/logic/aggregator.py` | `scan_market`, `run_fast_scan`, `process_pipeline`, `load_cache`, `save_cache`, `save_tier_shard`, `merge_tier_shards`, `precompute_dashboard_analytics` |
| `backend/logic/math_worker.py` | `run_math_task` (CPU-intensive, runs in ProcessPool) |
| `backend/logic/tier_manager.py` | `compute_tier_assignment`, `get_tier_tickers` (auto-assigns tickers to scan tiers by market cap) |
| `backend/scan_runner.py` | CLI entry for scanner subprocess (`--tier t1/t2` flag for tiered mode) |
| `backend/scheduler.py` | Standalone scheduler loop (LEGACY — paused, replaced by Cloud Run Jobs) |

### API Server

| File | Key Functions |
|------|--------------|
| `backend/api/main.py` | FastAPI app, routes, `merge_live_prices`, startup tasks |
| `backend/api/websocket_manager.py` | `ConnectionManager`, background schedulers, ticker tape |

### Data Ingestion

| File | Key Functions |
|------|--------------|
| `backend/logic/ingestion/gcs_client.py` | `GCSClient` singleton: `get_ticker_history`, `get_live_cache`, `get_gold_cache`, `upload_cache`, `promote_to_gold`, `upload_tier_shard`, `get_tier_shard`, `list_tier_shards`, `upload/get_tier_manifest` |
| `backend/logic/ingestion/polygon_wrapper.py` | `PolygonWrapper`: `get_stock_snapshots`, `get_daily_candles` |

### Supporting

| File | Key Functions |
|------|--------------|
| `backend/logic/pricing_engine.py` | `PricingEngine.update_all_prices` (5s real-time pricing) |
| `backend/logic/historical.py` | `consolidate_history`, `get_stock_history` (L5 read-through) |
| `backend/logic/lock_manager.py` | `SimpleFileLock` implementation (local OS locks) |

### Batch Scripts

| File | Purpose |
|------|---------|
| `scripts/ingest_all_parallel.py` | `SuperIngestor`: 20-year history bulk ingest to GCS |
| `backend/scripts/generate_processed_layer.py` | `ProcessedLayerGenerator`: per-ticker metrics to GCS |
| `backend/scripts/generate_gold_layer.py` | `GoldLayerGenerator`: historical Gold Layer backfill |

### Deployment

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage: node:20 (React build) + python:3.12 (backend) |
| `backend/start_gunicorn.sh` | Gunicorn entrypoint (2 workers, 300s timeout) |

---

## 13. CHANGES MADE (March 25-28, 2026)

### Critical Fixes

1. **NaT Row Corruption** (`aggregator.py`, `gcs_client.py`): Added `df = df[df.index.notna()]` at three defense layers to filter corrupted GCS data.

2. **Duplicate Startup Handlers** (`main.py`): Consolidated two `@app.on_event("startup")` handlers into one. Each scheduler now spawns exactly once.

3. **Processed Stats Fast Path Bypassing Live Data** (`aggregator.py`): Removed the processed stats fast path. All tickers now go through the full pipeline with live Polygon snapshot injection.

4. **Broken Function Names in Math Worker** (`math_worker.py`): Restored all original function names (`calc_rs_score` not `calculate_relative_strength`, etc.) and output columns.

### New Features

- **`DISABLE_SCAN_SCHEDULERS` env var** — Gate to disable heavy scanning on app server
- **Analytics JSON synced via GCS** — `upload_analytics()` / `download_analytics()` methods
- **SC-54 Live Price Injection** — `run_fast_scan()` now fetches Polygon batch snapshots
- **2-Tier Batch Scanning Architecture** — `tier_manager.py`, shard/merge system
- **Automatic Gold Layer Promotion** — after every `merge_tier_shards()`

### Improvements

- Cache staleness reduced: `max_age_seconds` changed from 1800 → 60
- Ticker tape: 60s refresh loop, jitter reduced from ±0.2% to ±0.01%
- Per-ticker math timeout raised from 30s to 60s
- Gold Layer backfill: 42/42 trading days in Jan 29 – Mar 27 range

---

## 14. THEME DISCOVERY PIPELINE (April 9, 2026)

### Architecture

Theme Discovery has two data paths serving different UI components:

```
Path A: Discovery Cache (SCAN tab, /api/thematic/discovery)
  refresh_global_themes.py → global_theme_cache.json → API reads cache → frontend

Path B: Theme History (DISCOVER tab + Dashboard cards, /api/thematic/discovery/history)
  refresh_global_themes.py → save_to_history() → Supabase theme_history table → API queries DB → frontend
```

**Frontend consumers:**
| Component | File | API Called | Data Source |
|-----------|------|-----------|-------------|
| Dashboard Theme Discovery cards | `src/components/intelligence/DiscoveryRail.tsx` | `fetchThematicHistory()` | Path B (Supabase) |
| SCAN tab (admin) | `src/pages/ThematicAnalysis.tsx` | `fetchThematicDiscovery()` | Path A (cache file) |
| DISCOVER tab | `src/pages/ThematicAnalysis.tsx` | `fetchThematicHistory()` | Path B (Supabase) |
| Market Pulse (Trending Themes) | `src/pages/MarketPulse.tsx` | `fetchThematicDiscovery()` | Path A (cache file) |

### Refresh Pipeline (`execution/core_backend_schedulers/refresh_global_themes.py`)

```
refresh_themes(force, limit_tickers)
  |
  +-- 1. Load market data (aggregator.load_market_data)
  +-- 2. Scan for outliers (min_strength=70, min_rel_vol=1.5)
  |      Cap at 100 outliers
  +-- 3. DBSCAN clustering (theme_engine.detect_clusters, correlation_threshold=0.70)
  +-- 4. Sort by viral_score descending
  +-- 5. PASS 1: Ticker-union dedup (collect up to 10 candidates)
  |      - Build running set of accepted tickers
  |      - Skip if >50% of cluster's tickers already in union
  |      - Tag similar_to from theme_history (7-day lookback, Jaccard >=0.40)
  +-- 6. PASS 2: Sector diversity soft cap
  |      - Uses TICKER_CATEGORY_MAP for dominant sector per theme
  |      - If >60% of top 5 share same sector AND alternatives exist:
  |        demote weakest same-sector, promote best different-sector
  |      - Re-sort by viral_score after swap
  +-- 7. AI enrichment (top 5: Linkup preferred, OpenAI fallback)
  +-- 8. Save cache (global_theme_cache.json, key: "themes")
  +-- 9. Archive to theme_history (Supabase, if viral_score >0.3 or fracture_risk High/Critical)
         - Dedup: 7-day lookback, Jaccard >=0.60 or exact name match
```

### PE Enrichment (Background Task)

PE ratios are NOT fetched in the hot API path. The `/api/thematic/discovery/history` endpoint returns results immediately from Supabase, then kicks PE enrichment into a FastAPI `BackgroundTask`:

```
GET /api/thematic/discovery/history
  |
  +-- Query Supabase theme_history (fast, ~200ms)
  +-- Dedup by theme_name (keep newest)
  +-- Return results immediately
  +-- Background: _enrich_theme_pe(results)
       +-- Load ETF taxonomy (filter ETFs from PE calc)
       +-- Collect tickers needing PE (max 5 per theme)
       +-- Fetch FMP ratios-ttm per ticker (sequential)
       +-- Persist avg_pe to theme_history rows
       +-- Next request gets cached PE values
```

**Key design decision**: PE appears on the *next* request, not the current one. This is intentional to keep the endpoint fast. The Global Alpha Matrix (PE x Viral Score scatter plot) may show dots at x=0 for one request cycle after fresh themes are written.

### Dedup Algorithm Details

**Pass 1 — Ticker-Union Coverage** (`UNION_COVERAGE_THRESHOLD = 0.50`):
- First accepted theme's tickers seed the union
- Each subsequent theme: compute `|tickers ∩ union| / |tickers|`
- If >=50% covered, skip (tickers already represented by prior themes)
- Otherwise accept and add tickers to union
- Collects up to 10 candidates for Pass 2

**Pass 2 — Sector Diversity Soft Cap** (`SECTOR_CAP_RATIO = 0.60`):
- Only runs if >5 candidates from Pass 1 AND TICKER_CATEGORY_MAP available
- Computes dominant sector per theme via majority vote of ticker sectors
- If >60% of top 5 share one sector: swap weakest same-sector for best different-sector
- If no alternatives exist (market genuinely one-sector), all 5 are kept
- Re-sorts by viral_score after swap

### Cache File Format

`backend/data/global_theme_cache.json`:
```json
{
  "timestamp": "2026-04-09T15:24:40.668",
  "themes": [
    {
      "theme_name": "Permian Power Surge",
      "viral_score": 0.88,
      "fracture_risk": "Low",
      "avg_return": 0.497,
      "leader": "APA",
      "tickers": ["CRC", "CHRD", "MGY", "APA"],
      "ai_summary": "...",
      "similar_to": null
    }
  ]
}
```

**Note**: Cache saves with `"themes"` key. The `/api/thematic/discovery` endpoint normalizes to `"clusters"` key for frontend compatibility (lines 2313-2315 of main.py).

### Known Limitations

1. **Quiet market empty state**: When min_strength=70 and min_rel_vol=1.5 find zero outliers, cache is saved as `"themes": []`. No fallback to curated static themes from `theme_manager.py`.
2. **DBSCAN parameter sensitivity**: correlation_threshold=0.70 is hardcoded. No adaptive logic for high/low correlation regimes.
3. **FMP rate limits**: Background PE task does sequential FMP calls with no quota tracking. FMP free tier is 250 calls/day.
4. **theme_history has no TTL**: Rows accumulate indefinitely. 7-day dedup window prevents short-term duplicates but not long-term repetition.
5. **save_to_history N+1 queries**: Each theme independently queries theme_history for dedup check, despite the refresh pipeline already having fetched this data.

### Incident Reference

See `technical_documentation/INC-20260409-theme-discovery-skeleton-loaders.md` for the full incident report on the PE enrichment blocking bug and its resolution.

---

## 15. OPTIONS DATA PIPELINE (April 9, 2026)

### Overview

The options pipeline collects option chain snapshots from Polygon.io, computes derived views (scanner rankings, thematic heat, IV/ETS divergence, GEX profiles), and stores everything in GCS. The API serves pre-computed data from GCS with in-memory caching, falling back to expensive on-demand Polygon scans only when GCS data is missing.

### Key Files

| File | Role |
|------|------|
| `backend/options_snapshot_runner.py` | CLI entry point — fetches chains, generates live views, uploads to GCS |
| `backend/routers/options_router.py` | API endpoints with 3-layer caching |
| `backend/logic/options_data_lake.py` | GCS reader with L0 local file cache |
| `backend/logic/engines/thematic_options_heat.py` | Aggregates options flow by 24 investment themes |
| `backend/logic/engines/iv_ets_divergence.py` | Detects IV vs ETS divergence signals |
| `backend/logic/engines/options_scanner_engine.py` | Volume leaders, IV rankings, P/C ratios |
| `backend/logic/options_tiers.py` | Tier definitions — resolves ticker lists dynamically |
| `execution/build_and_deployment_automation/deploy_options_tiers.sh` | Cloud Run Jobs + Scheduler deployment |

### Tiered Scan Architecture

| Tier | Tickers | Cadence | Resources | Timeout |
|------|---------|---------|-----------|---------|
| T1 | ~72 liquid names (SPY, QQQ, AAPL, NVDA, etc.) | Every 5 min | 2Gi / 1 CPU | 10 min |
| T2 | ~200 mid-liquidity names | Every 15 min | 2Gi / 1 CPU | 15 min |
| T3 | All ~2096 tickers | Every 60 min | 4Gi / 2 CPU | 30 min |

- Tickers resolved dynamically via `get_tier_tickers()` in `backend/logic/options_tiers.py` — no hardcoded ticker lists in deploy scripts
- All jobs use `--parallelism=1` to prevent concurrent GCS writes to the same date files
- Schedules: Mon–Fri 14:00–21:00 UTC (covers market hours in both EDT and EST with slight overshoot)
- Deployment: Cloud Run Jobs triggered by Cloud Scheduler (see `deploy_options_tiers.sh`, all commands commented out by default)

**Required secrets** (via Secret Manager):
`POLYGON_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`

### GCS Storage Layout

```
gs://flowlyte-data-lake-v1/options/
├── snapshots/{DATE}/                    # Raw chain data (Parquet, snappy)
│   ├── AAPL.parquet                     # Full option chain per ticker
│   ├── SPY.parquet                      #   (strike, expiry, type, iv, volume, oi, greeks)
│   ├── _summary.parquet                 # Index: avg_iv, contract_count, total_volume, total_oi
│   └── ...
└── live/{DATE}/                         # Derived views (JSON)
    ├── _scanner.json                    # Volume leaders, IV rankings, P/C ratios
    ├── _thematic_heat.json              # Theme-level options aggregation (NEW)
    ├── _iv_ets.json                     # IV vs ETS divergence signals (NEW)
    ├── _manifest.json                   # Run metadata
    ├── chains/{TICKER}.json             # Per-ticker chain with Greeks
    └── gex/{TICKER}.json               # Per-ticker gamma exposure profile
```

### JSON v2 Accumulated Format

Live view files use a versioned accumulated format. Each scan run appends an entry:

```json
{
  "version": 2,
  "entries": [
    { "scanned_at": "2026-04-09T14:05:00Z", "themes": [...] },
    { "scanned_at": "2026-04-09T14:10:00Z", "themes": [...] }
  ],
  "last_scanned_at": "2026-04-09T14:10:00Z"
}
```

The API returns only `entries[-1]` (latest), but full intraday history is preserved for time-series analysis. The `_accumulate_and_upload()` function handles downloading the existing file from GCS, appending the new entry, and re-uploading atomically.

### Live View Generation Pipeline

`generate_live_views()` in `options_snapshot_runner.py` produces 5 derived views per run:

```
generate_live_views()
  |
  +-- 1. chains/{TICKER}.json — per-ticker chain + Greeks from raw snapshot
  +-- 2. gex/{TICKER}.json — gamma exposure profile by strike
  +-- 3. _scanner.json — scan_all() (volume leaders, IV rankings, P/C ratios)
  +-- 4. _thematic_heat.json — scan_thematic_heat() (24 themes × 6 tickers max)
  +-- 5. _iv_ets.json — scan_iv_ets_divergence(top_n=100)
  +-- 6. _manifest.json — run metadata (date, ticker count, duration, errors)
```

Steps 4 and 5 call async engine functions via `asyncio.run()` within the synchronous pipeline. Both use `_accumulate_and_upload()` to merge into GCS.

### Three-Layer API Caching

```
Frontend Request → L1 In-Memory → L2 GCS Data Lake → L3 On-Demand Compute
```

**L1: In-memory response cache** (`_response_cache` dict in `options_router.py`):

| TTL Type | Duration | Endpoints |
|----------|----------|-----------|
| `chain` | 60s | Single-ticker chain |
| `gex` | 120s | Gamma exposure |
| `flow` | 30s | Live flow trades |
| `scanner` | 300s (5 min) | Scanner, thematic heat, IV/ETS |
| `screener` | 120s | Strategy screener |

Thread-safe expiry: uses `pop(key, None)` instead of `del` to avoid `KeyError` under concurrent asyncio access.

**L2: GCS Data Lake** (`OptionsDataLake` in `options_data_lake.py`):
- Downloads from GCS blob → writes to local L0 cache at `backend/cache/options_live/{DATE}/`
- L0 TTL: 300s (5 min) — avoids repeated GCS downloads within the window
- Returns `None` if blob doesn't exist, triggering L3 fallback

**L3: On-demand compute** (engine functions):
- Calls Polygon API directly: batch size 5, 0.4s sleep between batches
- Slowest path: 8–60 seconds depending on ticker count (69 DEFAULT_SCAN_TICKERS, 24 themes × 6 tickers)
- Result cached in L1 for subsequent requests

### Base-Result Caching Pattern (Thematic Heat & IV/ETS)

To avoid cache key explosion from filter parameter combinations, both endpoints use one cache key per date:

```
Traditional: thematic_heat:2026-04-09:AI,Semis:500  → N×M cache entries
Base-result: thematic_heat_base:2026-04-09           → 1 cache entry + in-memory filtering
```

1. Engine called with **no filters** — fetches all themes/signals for the date
2. Result cached under a single date-based key
3. `_apply_thematic_heat_filters()` / `_apply_iv_ets_filters()` apply user filters in memory

**IV/ETS filter** (`_apply_iv_ets_filters`):
- Filters by `min_ets` threshold, `signal_filter` type, `top_n` limit
- Summary dict always includes all 5 canonical types via `_IV_ETS_SIGNAL_TYPES`: `breakout_watch`, `building_momentum`, `expensive_momentum`, `fear_fade`, `neutral`
- Handles `None` ETS values with `(r.get("ets") or 0)`

**Thematic heat filter** (`_apply_thematic_heat_filters`):
- Filters by theme names (case-insensitive) and `min_volume` threshold on aggregated `total_volume`
- Recalculates `total_themes` and `hot_themes` counts after filtering (not stale base counts)

### Data Lake Accessor API

`OptionsDataLake` class (singleton via `get_options_lake()`) provides:

| Method | Returns |
|--------|---------|
| `get_scanner(date)` | Scanner results (volume leaders, IV rankings) |
| `get_thematic_heat(date)` | Theme-level options aggregation |
| `get_iv_ets(date)` | IV vs ETS divergence signals |
| `get_chain(date, ticker)` | Full option chain for a specific ticker |
| `get_gex(date, ticker)` | Gamma exposure profile |
| `get_scanner_history(dates)` | Multi-day scanner time series |
| `get_thematic_heat_history(dates)` | Multi-day thematic heat time series |
| `get_iv_ets_history(dates)` | Multi-day IV/ETS signal time series |

All methods handle GCS download, L0 caching, and v1/v2 format normalization automatically. Safe to call from AI agents.

### Thematic Heat Engine Details

`scan_thematic_heat()` in `thematic_options_heat.py`:
- Uses 24 investment themes from `theme_manager.py` (AI, Semis, Cybersecurity, etc.)
- Caps at `MAX_TICKERS_PER_THEME = 6` to limit scan latency
- For each theme: batch-fetches option chain snapshots from Polygon, aggregates volume, IV, P/C ratio
- Heat classification labels: Institutional Focus, High Volume/Weak Trend, Momentum Building, Elevated IV, Moderate Activity, Quiet
- Heat colors: emerald (hot), blue (warm) used for `hot_themes` counting

### IV/ETS Divergence Engine Details

`scan_iv_ets_divergence()` in `iv_ets_divergence.py`:
- Loads ETS (Exponential Trend Strength) scores from daily aggregator cache
- Batch-fetches IV from Polygon option chain snapshots (batch_size=5, 0.4s delay)
- Cross-references IV and ETS to classify divergence:
  - `breakout_watch` — low IV + high momentum (market hasn't priced in the trend)
  - `building_momentum` — moderate IV + rising trend
  - `expensive_momentum` — high IV + high momentum (priced in, risky)
  - `fear_fade` — high IV + weak trend (fear premium, potential fade)
  - `neutral` — no significant divergence

### Known Limitations

1. **`min_volume` semantic mismatch (CRITICAL)**: Engine's `min_volume` filters individual option contracts during Polygon data collection (default: 200). Router's post-cache `min_volume` filter applies to aggregated theme-level `total_volume`. A request with `min_volume=0` gets the 200-contract floor baked in. Needs either API contract change or parameter removal.
2. **Lake data schema validation**: No runtime check that GCS-precomputed schema matches engine schema field names. Engine schema changes could break lake-cached data.
3. **Cache-Control header**: `public` sent for user-filtered responses; CDN could serve wrong filter combination.
4. **No deduplication across tiers**: If T1 and T2 overlap on tickers, both write snapshots. The accumulated JSON format handles this gracefully (append-only), but parquet snapshots are overwritten.

### Previous Trading Day Fallback

When today's GCS data is missing (pre-market, job hasn't run yet, weekends, holidays), the router tries the previous trading day's data before falling back to expensive Polygon API calls. Applied to all 6 lake-backed endpoints.

```
L1 miss → L2 miss (today) → L2 retry (prev trading day) → L3 Polygon
```

- `_lake_get_with_fallback()` in `options_router.py` derives the previous trading day from the `today` string (not a second clock read) to avoid midnight-boundary races
- Max staleness guard: `_MAX_FALLBACK_DAYS = 3` — refuses to serve data older than 3 calendar days (prevents serving week-old data after long holiday weekends)
- All 6 fallback calls wrapped with `asyncio.to_thread()` to avoid blocking the event loop with synchronous GCS I/O
- Uses `is_trading_day()` and `get_prev_trading_day()` from `backend/logic/trading_calendar.py`

### Holiday Guard (Snapshot Runner)

`options_snapshot_runner.py` checks `is_trading_day()` immediately after date resolution. On weekends and market holidays, exits with `sys.exit(0)` so Cloud Run Jobs marks the execution as SUCCEEDED (no retry, no wasted Polygon API calls).

---

## 16. OPTIONS FLOW PERSISTENCE (April 10, 2026)

### Overview

Live options flow from the Polygon WebSocket is persisted to two stores: GCS parquet (raw trades, source of truth) and Supabase (per-ticker daily summaries + anomaly events, queryable by agents). Only trades with premium >= $10,000 are persisted (institutional-grade flow).

### Key Files

| File | Role |
|------|------|
| `backend/logic/engines/flow_persistence.py` | FlowPersistence class — GCS parquet writes + Supabase upserts |
| `backend/logic/engines/options_flow_ws.py` | WebSocket consumer — classifies trades, detects anomalies, triggers flush |
| `backend/logic/engines/flow_anomaly_detector.py` | FlowAnomalyDetector — premium spikes, sweep clusters, volume surges |
| `backend/migrations/39_options_flow_daily_and_anomalies.sql` | Supabase tables + atomic upsert RPC |

### Data Flow

```
Polygon WebSocket (T.* options trades, 300-500/min during market)
    |
    [premium < $10K? → DROPPED]
    |
    v
OCC Parse → Classify (block/sweep/notable/normal) → Sweep Detect (2s window)
    |
    +──→ Ring Buffer (maxlen=2000, in-memory)
    |
    +──→ SSE Broadcast to frontend listeners
    |
    +──→ Anomaly Detection → route to Sentinel/Guardian/Webhook
    |                       → buffer to FlowPersistence._anomaly_buffer
    |
    v
_periodic_flush() — every 5 min (wall-clock asyncio task)
    |
    +──→ snapshot = list(ring_buffer)  [taken in event loop before threading]
    |
    +──→ asyncio.to_thread(flow_persistence.flush, snapshot)
         |
         +── 1. _flush_anomalies() → batch insert to options_flow_anomalies
         +── 2. Filter new trades (ts >= _last_flush_ts, premium >= $10K)
         +── 3. _append_to_gcs() → dedup + merge into daily parquet
         +── 4. _upsert_daily_summaries() → aggregate by ticker, RPC upsert
```

### Supabase Tables

**`options_flow_daily`** — one row per ticker per trading date, upserted every 5 min:

| Column | Type | Description |
|--------|------|-------------|
| ticker | TEXT | Underlying symbol |
| trade_date | DATE | Trading date |
| call_premium | DOUBLE | Total $ spent on calls |
| put_premium | DOUBLE | Total $ spent on puts |
| net_premium | DOUBLE | call_premium - put_premium (derived) |
| total_premium | DOUBLE | call_premium + put_premium (derived) |
| call_count | INTEGER | Number of call trades |
| put_count | INTEGER | Number of put trades |
| total_count | INTEGER | call_count + put_count (derived) |
| block_count | INTEGER | Trades with premium >= $100K |
| sweep_count | INTEGER | Cross-exchange sweeps |
| notable_count | INTEGER | Trades with size >= 50 contracts |
| pc_ratio | DOUBLE | put_count / call_count (derived) |
| sentiment_score | DOUBLE | (net_premium / total_premium) × 100 (derived) |
| top_trade_premium | DOUBLE | Largest single trade premium for the day |
| anomaly_count | INTEGER | Number of anomaly events for this ticker/date |
| updated_at | TIMESTAMPTZ | Last upsert time |

Unique constraint: `(ticker, trade_date)`. Indexed on `trade_date`, `ticker`, `sentiment_score`, and `total_premium DESC`.

**`options_flow_anomalies`** — individual anomaly events:

| Column | Type | Description |
|--------|------|-------------|
| ticker | TEXT | Affected underlying |
| trade_date | DATE | Date of anomaly |
| anomaly_type | TEXT | `premium_spike`, `sweep_cluster`, `volume_surge` |
| severity | TEXT | `high` (>= $1M) or `medium` |
| premium | DOUBLE | Premium that triggered the anomaly |
| details | JSONB | Full anomaly context (type-specific fields) |
| created_at | TIMESTAMPTZ | When the anomaly was detected |

### Atomic Upsert RPC

`upsert_flow_daily()` — single-statement INSERT...ON CONFLICT that atomically:
1. Accumulates raw counts (call/put premium, counts, block/sweep/notable counts)
2. Derives `total_count`, `net_premium`, `total_premium`, `pc_ratio`, `sentiment_score` from accumulated totals
3. Takes `GREATEST` of `top_trade_premium` (keeps the day's largest trade)

PostgreSQL evaluates all `EXCLUDED.*` and `options_flow_daily.*` references in the ON CONFLICT SET clause using a single pre-update snapshot, so accumulation and derived field computation are consistent even under concurrent callers.

### Anomaly Buffer

- Events buffered in a plain `list[dict]` with manual bound at 2000
- `record_anomaly()` shallow-copies the dict (isolates from async routing mutations), logs and drops oldest on overflow
- `_flush_anomalies()` uses atomic drain: snapshot buffer → clear → insert → restore on failure
- Anomalies flushed first in `flush()`, independent of GCS health

### Anomaly Detection Thresholds

| Type | Trigger | Min Premium | Window | Cooldown |
|------|---------|-------------|--------|----------|
| Premium Spike | Single trade >= 5× rolling median for ticker | $250K | 50-trade rolling median | 15 min/ticker |
| Sweep Cluster | >= 3 sweeps on same ticker | $250K aggregate | 2 minutes | 15 min/ticker |
| Volume Surge | >= 10 trades on same contract | $250K aggregate | 5 minutes | 15 min/contract |

Severity: `high` if >= $1M, `medium` otherwise.

### GCS Flow Storage

```
gs://flowlyte-data-lake-v1/options/flow/{YYYY-MM-DD}/trades.parquet
```

Parquet schema (18 columns): `underlying`, `contract`, `strike`, `expiry`, `type`, `size`, `price`, `premium`, `exchange`, `timestamp`, `timestamp_readable`, `classification`, `sentiment`, `iv`, `delta`, `oi`, `volume`

Dedup key: `(contract, timestamp, size, price)` — prevents duplicate writes across flush cycles. Timestamp filter uses `>=` (not `>`) to avoid losing trades at the nanosecond boundary.

### Periodic Flush Architecture

- Dedicated `_periodic_flush()` asyncio task runs on true 5-min wall clock (not gated on trade count)
- Task stored as `self._flush_task` — guarded with `done()` check on start, cancelled on `stop()`
- Takes `list(self._ring_buffer)` snapshot in the event loop, then dispatches `flush()` to `asyncio.to_thread()`
- GCS + Supabase I/O never blocks the event loop

### What Agents Can Query

From `options_flow_daily`:
- "Which tickers had the heaviest call flow today?" → `ORDER BY call_premium DESC`
- "Show me bearish sweep activity this week" → `WHERE sweep_count > 0 AND sentiment_score < -20`
- "What's the P/C ratio trend for NVDA?" → multi-day query on `pc_ratio`

From `options_flow_anomalies`:
- "Any premium spikes today?" → `WHERE anomaly_type = 'premium_spike' AND trade_date = today`
- "Sweep clusters on AI stocks" → join with theme tickers

From GCS parquet (via `FlowPersistence.load_historical()`):
- Full trade-level detail for deeper analysis
- Every individual trade >= $10K with classification, Greeks (when available)

### Known Limitations

1. **`_last_flush_ts` not persisted**: Resets to 0 on process restart. First flush after restart re-processes all ring buffer trades. GCS dedup prevents duplicate parquet rows, but Supabase summaries may double-count if the same trades are upserted twice.
2. **Anomaly dedup**: No unique constraint on `options_flow_anomalies`. Process restart during flush interval could re-detect and re-persist the same anomaly.
3. **IV/delta/OI not in WebSocket**: These fields are always `None`/`0` in flow trades. Only available from REST chain snapshot endpoints.

---

## 17. AGENT OPTIONS INTELLIGENCE PIPELINE (April 10, 2026)

### Overview

Wires options data (Supabase + GCS) into the LangGraph AI agent system via 6 tool functions. Before this, agents were completely blind to options activity. Now SentinelAnalyst, GuardianPortfolio, SentinelScout, and SentinelMacro can query institutional flow, anomalies, GEX profiles, thematic heat, IV/ETS signals, and chain summaries.

### Key Files

| File | Role |
|------|------|
| `backend/logic/tools/options_tools.py` | 6 tool functions + OpenAI schemas |
| `backend/logic/agents/sentinel_analyst.py` | Registers all 6 OPTIONS_TOOLS |
| `backend/logic/agents/guardian.py` | Flow + anomalies + proactive `check_portfolio_flow_risk` |
| `backend/logic/agents/sentinel_scout.py` | Thematic heat + anomalies |
| `backend/logic/agents/sentinel_macro.py` | Flow + thematic heat for macro context |
| `backend/logic/tools/intelligence_tools.py` | New `options` domain (6th in INTELLIGENCE_TOOLS) |
| `backend/logic/engines/health_engine.py` | Handles option positions, pre-builds markdown table |
| `directives/guardian_portfolio_directive.md` | Proactive behavior + table format instructions |

### The 6 Agent Tools

| Tool | Data Source | Purpose |
|------|-------------|---------|
| `fetch_options_flow` | Supabase `options_flow_daily` | Per-ticker or market-wide institutional flow (premium, sentiment, sweeps, blocks) |
| `fetch_flow_anomalies` | Supabase `options_flow_anomalies` | Premium spikes, sweep clusters, volume surges |
| `fetch_options_gex` | GCS `gex/{TICKER}.json` | Gamma exposure profile with key levels (max gamma, put wall, call wall) |
| `fetch_thematic_heat` | GCS `_thematic_heat.json` | Options activity aggregated by 24 investment themes |
| `fetch_iv_ets_signals` | GCS `_iv_ets.json` | IV vs ETS divergence signals (breakout_watch, fear_fade, etc.) |
| `fetch_options_chain_summary` | GCS `chains/{TICKER}.json` | ATM IV, total OI/volume, notable strikes |

All tools use:
- `asyncio.to_thread` dispatch (non-blocking)
- Ticker validation (regex `^[A-Z]{1,5}(\.[A-Z])?$`)
- Date validation (YYYY-MM-DD format)
- Sanitized errors (log server-side, return generic message to LLM)
- Previous trading day fallback for GCS data
- Days cap (30 for flow, 14 for anomalies)
- Limit cap (100 for flow, 200 for anomalies)

### Agent Tool Assignment

| Agent | Tools Available |
|-------|----------------|
| **SentinelAnalyst** | All 6 (flow, anomalies, GEX, thematic heat, IV/ETS, chain summary) |
| **GuardianPortfolio** | Flow, anomalies, `check_portfolio_flow_risk` (proactive) |
| **SentinelScout** | Thematic heat, anomalies, + `options` intelligence domain |
| **SentinelMacro** | Flow, thematic heat, + `options` intelligence domain |
| **SentinelScanner** | Via Analyst delegation only |

### Options Intelligence Domain

`fetch_intelligence_snapshot(domain="options")` synthesizes a daily options summary on-the-fly from Supabase:

```
{
  "domain": "options",
  "date": "2026-04-10",
  "source": "supabase",
  "note": "Returns most recent trading day (top-20 sample)",
  "data": {
    "market_sentiment": { "score": 23.4, "label": "bullish",
                          "total_call_premium": ..., "total_put_premium": ... },
    "top_flow_tickers": [...],     # Top 5 by premium
    "sweep_leaders": [...],        # Top 5 by sweep count (same query, no extra call)
    "high_anomalies": 3,
    "anomaly_summary": [...]       # Top 5 high-severity events
  }
}
```

**Important constraints**:
- Single Supabase query for flow (derives sweep leaders from same 20-row result)
- Separate query for anomalies (different table)
- Returns error (not zero-filled "neutral") if BOTH queries fail
- `date` parameter accepted for interface consistency but always returns most recent trading day
- `options` domain NOT supported for `fetch_intelligence_range` — use `fetch_options_flow` with `days=N` instead

### Guardian Proactive Flow Risk

`check_portfolio_flow_risk` is a proactive tool that Guardian calls automatically on "how is my portfolio?" queries:

```
Step 1: Get holdings via PortfolioTools.fetch_holdings()
Step 2: Extract underlying tickers from stock symbols + OCC option contracts
  - Uses _extract_underlying() regex: ^[A-Z]{1,5}(?:\.[A-Z])?
  - "AAPL 260417C00252500" → "AAPL"
  - Deduplicates: 4 QCOM options + 0 QCOM stock = 1 QCOM query
Step 3: Aggregate by underlying with combined P&L and option_contracts count
Step 4: Query anomalies (market-wide, filter locally to held tickers)
Step 5: Query flow sentiment per underlying in PARALLEL via asyncio.gather
  - Cap: 20 tickers (_MAX_FLOW_TICKERS)
  - Sorted by position size (largest P&L first) so cap covers highest-risk holdings
Step 6: Flag signals:
  - Bearish flow: sentiment_score < -20
  - Sweep clusters: sweep_count >= 3
  - Heavy puts: pc_ratio > 2.0
  - Anomaly events (premium_spike, sweep_cluster, volume_surge)
```

**Returns**:
- `total_underlyings`, `stock_positions`, `option_contracts`
- `holdings_summary` — per-underlying with stock/option counts, combined P&L
- `risk_flags` — per-ticker with list of triggered signals
- `risk_flags_by_ticker` — dict keyed by underlying for easy inline joining
- `data_warnings` — failed fetches, skipped holdings, anomaly truncation

### Health Engine Option Handling

`PortfolioHealthEngine.calculate_health()` was updated to handle option positions:

1. **Underlying extraction**: Option symbols (OCC format) resolved via `_extract_underlying()` regex. Cache lookups (sector, FT_Score, SMA50) use the underlying, not the raw OCC symbol.

2. **Options inherit metrics from underlying**: An `AAPL 260417C00252500` position gets `sector="Technology"`, `ft_score=<AAPL's>`, etc. Before this fix, options always landed in "Other" sector with `ft_score=0`, inflating the concentration warning.

3. **All holdings returned, not just movers**: The previous response only included top 10 by daily change %. Options with `change_pct=0` never made the cut. Now returns complete `all_holdings` list sorted by value.

4. **Pre-built markdown table**: `holdings_markdown_table` field contains a ready-to-paste markdown table. The Guardian directive instructs the LLM to paste it VERBATIM rather than reconstructing from `all_holdings` — prevents the LLM from silently dropping option rows with sparse P&L data.

5. **Fast path**: `include_analytics` defaults to False. Previously always ran `AnalyticsEngine.compute()` which fetches 5y OHLCV + replays every trade day-by-day (30s-2min). Now only runs on explicit request.

### Table Format (pre-built server-side)

```
| Ticker | Type | Weight | P&L % | P&L $ | Sector |
|--------|------|--------|-------|-------|--------|
| QQQ | STK | 43.65% | +5.78% | +$1,203 | Global Indices |
| QCOM 260417C00252500 | OPT | 1.18% | -98.66% | -$1,450 | Technology |
```

### Performance Optimizations

| Before | After | Savings |
|--------|-------|---------|
| `AnalyticsEngine.compute()` on every health call (5y OHLCV + trade replay) | Skipped by default, opt-in via `include_analytics=True` | 30s-2min |
| Sequential per-ticker flow queries in Guardian | `asyncio.gather` — 20 parallel via asyncio.to_thread | ~1s → ~80ms |
| Redundant 3rd Supabase query for sweep leaders in options intelligence | Derived from same top-20 result | One fewer round-trip |
| Always hitting Polygon for GCS-backed endpoints | Previous trading day fallback + 3-day staleness guard | 8-60s per miss |

### What the Agents Can Answer Now

**SentinelAnalyst:**
- "What's the options flow on NVDA today?"
- "Where's the SPY gamma wall?"
- "Find cheap options on momentum stocks"
- "Any unusual activity on AAPL this week?"

**GuardianPortfolio (proactive):**
- "How is my portfolio?" → calls `fetch_portfolio_health` AND `check_portfolio_flow_risk` together
- "Any risk on my holdings?" → scans all held underlyings for flow anomalies
- "What's the flow on my holdings?" → per-ticker flow for each held underlying

**SentinelScout:**
- "Which themes have institutional options heat?"
- "Is AI seeing heavy call flow?"

**SentinelMacro:**
- "Is options flow risk-on or risk-off?"
- "What does sector flow say about macro positioning?"

**Via intelligence domain (Analyst, Scout, Macro):**
- `fetch_intelligence_snapshot(domain="options")` — single-shot daily options briefing

### Known Limitations

1. **GCS-backed tools (GEX, thematic heat, IV/ETS, chain summary) return empty until Cloud Run Jobs are deployed.** Without the tiered snapshot runner writing to GCS, these endpoints fall back to expensive on-demand Polygon scans (8-60s).

2. **Options pricing needs live market data**: Outside market hours, option positions show `pnl_percent=0` and `change_pct=0` because `live_prices` table has no fresh option marks. Health report displays them but P&L columns are flat.

3. **LLM row-dropping mitigated but not eliminated**: The pre-built markdown table prevents the LLM from silently filtering options, but some models still ignore "paste verbatim" instructions. If it happens again, the next mitigation is to inject the table directly into the final response outside the LLM's control.

4. **20-ticker cap on Guardian flow scan**: Portfolios with more than 20 holdings have smaller positions skipped. Sorted by absolute P&L so largest exposure is always scanned first. `data_warnings` surfaces the skipped count.

5. **`_last_flush_ts` restart caveat**: Backend restart mid-market-hours can cause first flush to double-count Supabase summaries for trades currently in the ring buffer. GCS parquet dedup is unaffected.

6. **Options intelligence is top-20 biased**: `market_sentiment` in the `options` intelligence domain is computed from only the top 20 tickers by premium, not a full market aggregation. Documented in the `note` field.

### Market-Open Checklist

When markets open and flow data starts populating:

| Check | How |
|-------|-----|
| WebSocket receiving trades | `SELECT COUNT(*) FROM options_flow_daily WHERE trade_date = CURRENT_DATE` should grow |
| Anomalies firing | `SELECT COUNT(*) FROM options_flow_anomalies WHERE trade_date = CURRENT_DATE` — may be zero for first 15-30 min |
| Agent can query flow | Ask: "Options flow on SPY today" — should return populated data |
| Portfolio P&L populated | Ask Guardian: "How is my portfolio?" — option positions should show real daily change |
| GCS-backed tools work | Ask: "Where's the SPY gamma wall?" — requires Cloud Run Jobs deployed |

**Dependencies**:
- `POLYGON_API_KEY` env var set
- Backend running during market hours (WebSocket auto-starts 15s after boot via `schedule_options_flow_ws` in `backend/api/main.py:452`)
- Supabase migration 39 applied (tables + `upsert_flow_daily` RPC)
- Cloud Run Jobs deployed per `deploy_options_tiers.sh` (for GCS pre-compute pipeline)

### Incident Reference

See `docs/agent-options-intelligence-pipeline.md` for the original plan and `docs/agent-options-test-cases.md` for test cases.
