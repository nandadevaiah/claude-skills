---
name: flowlyte-domain-expert
description: >
  Complete domain knowledge for Flowlyte.app — a top-down market intelligence platform
  for traders and investors. Covers every proprietary metric (FT_Score, FVS, ETS, RS_Score),
  user workflows (Economy > Sectors > Companies), AI agent system, data pipeline,
  subscription tiers, and product architecture.
version: 1.0.0
source: local-repo-analysis
---

# Flowlyte Domain Expert

Flowlyte is a **top-down market intelligence platform** that surfaces real-time intelligence for traders and investors. The core philosophy is a structured research workflow: **Economy > Sectors/Themes > Individual Companies**, combined with proprietary scoring, AI agents, portfolio management, and a trading journal.

---

## 1. PRODUCT PHILOSOPHY & USER WORKFLOW

### The Top-Down Research Flow

```
1. MACRO ECONOMY (/macro)
   Where does the economy stand? What cycle phase are we in?
   ↓
2. MARKET BREADTH (/breadth)
   Which sectors are leading/lagging? How healthy is participation?
   ↓
3. THEMATIC ANALYSIS (/themes)
   What narratives are driving capital? AI, Semis, GLP-1, Nuclear?
   ↓
4. SCREENER / SQUEEZE RADAR (/screener, /squeeze-radar)
   Which stocks have the best technical setups right now?
   ↓
5. INDIVIDUAL STOCK (/ticker/:symbol)
   Deep dive: fundamentals, technicals, options, AI insights
   ↓
6. PORTFOLIO & JOURNAL (/portfolio, /journal)
   Execute, track, and review trades
```

### Target Users
- **Active Traders**: Day/swing traders looking for momentum setups, squeeze breakouts, options flow
- **Investors**: Long-term holders analyzing macro cycles, sector rotation, and fundamental value
- **Options Traders**: IV analysis, flow tracking, Greeks management, payoff simulation

---

## 2. PROPRIETARY SCORING METRICS

### 2.1 FT_Score (Flow/Technical Score)

**The core directional momentum score per timeframe.**

- **Range**: -15 to +15
- **Calculation**: `FT_Score = Bull_Score - Bear_Score`
- **15 Bull Conditions** (each = 1 point if true):
  1. MACD Histogram > 0
  2. SMA50 rising
  3. EMA21 rising
  4. SMA200 rising
  5. SP Pattern: EMA5 > EMA8 > EMA21 > EMA34, EMA21 > SMA50
  6. Close > EMA21
  7. Close > SMA50
  8. Close > SMA200
  9. EMA8 > EMA21
  10. EMA8 > SMA50
  11. EMA8 > SMA200
  12. EMA21 > SMA50
  13. EMA21 > SMA200
  14. SMA50 > SMA200
  15. Supertrend Direction = +1
- **15 Bear Conditions**: Exact inverse
- **Timeframes calculated**: W, 4D, 3D, 2D, D, 4h, 2h, 1h, 30m, 15m
- **Key thresholds**: > 10 = strong bullish, < -10 = strong bearish
- **A+ Setup**: SQZ = True AND FT_Score > 14 (bull) or < -14 (bear) — highest conviction signal
- **File**: `backend/logic/score_engine.py`

### 2.2 Trend_Strength (Aggregate Multi-Timeframe Score)

**Overall momentum alignment across all timeframes.**

- **Range**: 0-100%
- **Calculation**: `(Sum of FT_Score across 8 timeframes) / (15 x 8) x 100`
- **Timeframes**: 4D, 3D, 2D, D, 4h, 2h, 1h, 30m
- **Interpretation**: > 70% = strong bullish alignment, < 30% = strong bearish, ~50% = neutral/mixed
- **File**: `backend/logic/math_worker.py`

### 2.3 FVS (Flowlyte Volume Spread)

**Detects smart money flows by measuring price spread weighted by volume.**

Three components:

#### FVS_Val (Raw Value)
```
v = volume / volume[1]                    # Volume ratio
vmac = EMA(close, 10) x v                # Volume-weighted close
vmao = EMA(open, 10) x v                 # Volume-weighted open
FVS_Val = vmac - vmao                    # Volume spread
FVS_Signal = EMA(FVS_Val, 20)           # Signal line
```

#### FVS_Pct (Normalized Percentage)
```
FVS_Pct = (FVS_Val / Close) x 100       # Cross-ticker comparable
```

#### FVS_Z_Score (Statistical Strength)
```
60-period rolling mean/stddev of signal
Z_Score = (current_signal - mean_60) / std_60
```

- **Bullish**: FVS_Val positive, Z_Score > 1 = institutional buying
- **Bearish**: FVS_Val negative, Z_Score < -1 = institutional selling
- **Crossover signals**: FVS_Up (crosses above 0), FVS_Down (crosses below 0)
- **File**: `backend/logic/engines/volume.py`

### 2.4 RS_Score (Relative Strength vs SPY)

**How strongly a stock outperforms or underperforms the market.**

- **Range**: -10 to +10
- **Calculation**:
  ```
  rs = close / SPY_close
  change_1d, 5d, 10d, 20d = % change in ratio
  trend_score = (s1 x 1) + (s5 x 2) + (s10 x 3) + (s20 x 4)
  RS_Score = EMA(trend_score, 8)
  ```
- **Weights**: Longer timeframes weighted more heavily (20d = 4x weight of 1d)
- **Interpretation**: > 6 = strong outperformer, < -6 = weak underperformer
- **RS_Change**: Day-over-day acceleration/deceleration
- **File**: `backend/logic/engines/trend.py`

### 2.5 ETS (Exponential Trend Strength)

**Composite momentum score with weighted sub-metrics.**

- **Range**: 0-100
- **Formula**: `ETS = (35% x Change) + (20% x RelVol) + (35% x RS) + (10% x ATR)`
- **Sub-metrics**:
  - Change Sub (35%): Daily % change, sigmoid-normalized to 0-100
  - RelVol Sub (20%): Volume vs 20-day avg, linear 0-100
  - RS Sub (35%): RS Z-Score, sigmoid-normalized to 0-100
  - ATR Sub (10%): Inverted ATR% (lower volatility = higher score), dead tape penalty
- **Badge System**:
  | ETS Range | Badge | Meaning |
  |-----------|-------|---------|
  | >= 85 | A+ Early-Turn | Exceptional momentum |
  | 75-84 | A Early-Turn | Strong acceleration |
  | 65-74 | B Setup | Good setup |
  | 55-64 | C Watch | Developing |
  | < 55 | D Low | Weak |
- **File**: `backend/logic/engines/ets_engine.py`

### 2.6 Squeeze Detection

**Volatility compression indicating potential breakout.**

- **Method**: Bollinger Bands inside Keltner Channel
  ```
  BB = Bollinger(close, 20, 2.0)
  KC_Upper = EMA(close, 20) + 1.75 x ATR(20)
  Squeeze = BB_Upper < KC_Upper
  ```
- **When True**: Price compressed, breakout imminent
- **A+ Setup**: Squeeze + FT_Score > 14 (or < -14) = highest conviction
- **BB_Width**: `(BB_Upper - BB_Lower) / BB_Mid` — lower = tighter compression
- **Multi-timeframe**: Squeeze tracked on W, 2D, D, 4h separately
- **File**: `backend/logic/score_engine.py`

### 2.7 VW Keltner (Volume-Weighted Keltner Channel)

**Enhanced Keltner that incorporates volume anomalies.**

- **Three variants**: Normal ATR, Z-Score Factor ATR, VW Smooth ATR
- **Master band**: Max of all three (widest)
- **Phantom band**: Min of all three (tightest)
- **Shadow band**: Median of all three
- **VW_Divergence**: % difference between VW and normal channels — flags volume-driven volatility expansion
- **Vol_ZScore**: `(current_vol - 20-period mean) / stddev`
- **File**: `backend/logic/vw_keltner.py`

### 2.8 ATR Extension

**How overextended price is from the mean.**

- **Calculation**: `(Close - EMA21) / ATR14`
- **Interpretation**: Number of ATRs from the 21-period EMA
- **+2.5**: Significantly overextended bullish (mean reversion risk)
- **-2.5**: Significantly overextended bearish
- **0 to +/-1.25**: Normal trading range
- **File**: `backend/logic/engines/volatility.py`

### 2.9 Price Location

**Where price sits within its 52-week range.**

- **Calculation**: `((Close - 252d_Low) / (252d_High - 252d_Low)) x 100`
- **Range**: 0-100%
- **90-100%**: Near 52-week highs (momentum), **0-10%**: Near 52-week lows
- **File**: `backend/logic/math_worker.py`

### 2.10 Sequencer (Wyckoff-Inspired Setup Detection)

**Counts consecutive preparation bars for trend reversals.**

- **Bull Prep**: Count of consecutive bars where Close < Close[4 bars ago]
- **Bear Prep**: Count of consecutive bars where Close > Close[4 bars ago]
- **Perfect Setup**: Count reaches 9 — ready for major move
- **File**: `backend/logic/sequencer.py`

### 2.11 Additional Technical Metrics

| Metric | Calculation | Interpretation |
|--------|-------------|----------------|
| **Z_Score** (multiple windows) | `(Close - SMA_w) / StdDev_w` for w=5,10,20,30,60,90,126,252 | > 2.0 extreme bullish, < -2.0 extreme bearish |
| **Rel_Vol** | `current_volume / SMA(50 prior volumes)` | > 2.0 = volume surge |
| **Sell_Vol_Pct** | `V x (H - C) / (H - L) / V x 100` | > 60% sellers dominate, < 40% buyers dominate |
| **Vol_ZScore** | `(current_vol - mean_20) / std_20` | > 3.0 = climax volume |
| **RSI(14)** | Standard momentum oscillator | > 70 overbought, < 30 oversold |
| **ADX(14)** | Trend strength | > 25 strong trend |
| **MACD** | Fast=24, Slow=52, Signal=9 | Histogram sign = momentum direction |
| **Supertrend** | Length=9, Mult=2.4 | +1 uptrend, -1 downtrend |
| **MFI(14)** | Volume-weighted RSI | > 80 overbought, < 20 oversold |
| **Stochastic(14,3,3)** | Momentum oscillator | > 80 overbought, < 20 oversold |

---

## 3. PAGES & FEATURES

### 3.1 Macro Economy (`/macro`) — PRO

Understand the economic cycle. Four phases: **Recovery, Expansion, Late-Cycle, Contraction**.

**Detection method**: 25 signal pairs (ratio analysis of sector/asset ETFs) across 3 windows (21, 63, 126 days), weighted by category:
- Equity Leadership (35%): XLY/XLP, XLF/XLU, XLI/XLV, RSP/SPY, IWM/SPY, etc.
- Rates & Curve (30%): TLT/IEF, IEF/SHY, TIP/IEF
- Credit Spread (10%): HYG/LQD
- Real Assets (15%): VNQ/IEF, GLD/CPER, USO/GLD, DBC/IEF
- Dollar (5%): UUP/DBC

**Views**: Playbook (radar + metrics), Details (signal table), Barometer (yield curve, VIX, credit spreads, breadth)

### 3.2 Market Breadth (`/breadth`) — PRO

Sector rotation and participation analysis.

**Views**: Market Map (treemap heatmap), RS Z-Score charts, Sector Rotation (RRG chart), Trend Trajectories, Strength Heatmap, Sector Deep Dive, Volume & Pressure

**Periods**: Today, Yesterday, This Week, Last Week, This Month, Last Month, This Quarter, Last Quarter, YTD, 1 Year

### 3.3 Thematic Analysis (`/themes`) — PRO

Discover and monitor market themes.

**Tabs**:
- **Monitor**: Live theme performance matrix (AI & Tech, Healthcare, Defense, Clean Energy, etc.)
- **Rotation**: Capital flow visualization, momentum vs RS scatter, sector flows
- **Discovery**: DBSCAN correlation clustering to find organic themes
  - Viral Score (0-1): Multi-factor momentum
  - Fracture Risk: Leader concentration risk
  - Archetype: Hyper Bubble / Deep Value / Growth at Value / Value Trap
  - AI narrative generation (Gemini LLM)

**Static Theme Library** (11 categories): AI, Semiconductors, Cybersecurity, Cloud, Fintech, Clean Energy, Biotech, Defense, Uranium, Weight Loss (GLP-1)

### 3.4 Market Pulse (`/pulse`) — FREE

Daily market snapshot: indices, breadth metrics, sector rotation chart, trending themes, opportunity table with top movers.

### 3.5 Screener (`/screener`) — HYBRID

Market-wide stock scanner with 50+ filterable columns.

**Free**: Basic views (top 10 results). **PRO**: Advanced filters (ETS, squeeze, volume, FVS), unlimited results, CSV export.

**Key columns**: Ticker (with multi-timeframe squeeze dots), FT_Score (heatmap), Trend_Strength, RS_Score, ETS badge, FVS metrics, fundamentals, volume metrics.

### 3.6 Squeeze Radar (`/squeeze-radar`) — PRO

Dedicated squeeze monitoring. Scatter plot (Trend Strength Y-axis vs Tightness X-axis). Segmented tables: Major Indices, Theme ETFs, Big 10, all stocks. Multi-timeframe columns.

### 3.7 Strategy Lab (`/strategy-lab`) — PRO

Pre-defined strategy gallery + backtesting engine. Equity curves, drawdown charts, Sharpe/Sortino ratios, trade lists.

### 3.8 Ticker Page (`/ticker/:symbol`) — FREE (partial)

**Tabs**: Overview, Fundamentals (FMP deep dive), Insights (AI research card), Chart (TradingView), Holdings, Earnings, Options (PRO), Flow (PRO)

### 3.9 Option Corner (`/options`) — PRO

**Tabs**: Flow (unusual volume, blocks, sweeps), Scanner (6 pre-built scans), Chain (full Greeks), Volatility (IV rank, term structure, skew), Simulator (multi-leg position builder)

### 3.10 Portfolio (`/portfolio`) — PRO

Holdings tracking with FIFO P&L. **Analytics tabs**: Overview (KPI cards), Growth (equity curve), Risk (beta, VaR, correlation), Diversification, Dividends, Metrics (Greeks), Reporting. Broker integration via Alpaca.

### 3.11 Trading Journal (`/journal`) — PRO

**Tabs**: Overview (stats), Trade Log, Day View (daily notes + performance), Notebook (rich text), Strategies (templates), Campaigns (multi-trade groupings)

### 3.12 Campaigns (`/campaigns`) — PRO

Group related trades into thematic campaigns. Track thesis, P&L lifecycle, adjustment history, exposure analysis.

### 3.13 Economic Calendar (`/calendar`) — FREE

Economic events by country/importance + earnings calendar. AI analysis of event impact via Sentinel.

### 3.14 Daily Briefing & Market Digest

**Daily Briefing**: AI-generated market summary — key moves, macro themes, sector rotation, risk alerts, opportunity highlights. Generated from theme cache, FMP calendars, scanner data, watchlists.

**Market Digest**: Curated intelligence tabs — Traders (day trading ideas), Investors (long-term picks), Context (macro), Customize (user presets).

---

## 4. AI AGENT SYSTEM

Built with **LangGraph + LangChain + OpenAI**. Initialized once at startup in `main.py`.

### Agent Hierarchy

```
User Query
  ↓
SentinelChatAI (Supervisor/Router)
  ├── SentinelLead (Orchestrator) — delegates to sub-agents
  ├── SentinelAnalyst (Technical Analyst) — ticker analysis, SMC, Wyckoff
  ├── SentinelMacro (Economist) — rates, inflation, cycle positioning
  ├── SentinelScout (Theme Scout) — narratives, viral themes, clusters
  ├── GuardianPortfolio (Risk Officer) — portfolio health, hedging, sizing
  ├── SentinelScanner (Screener) — universe-wide filtering
  ├── SentinelWebHelper (Web Research) — external data, news
  └── Janitor (Maintenance) — cache cleanup, data integrity
```

**Context injection**: user_id, watchlist, portfolio data passed to agents. Stateful conversation within session.

**Files**: `backend/logic/agents/ceo_graph.py`, `backend/logic/agents/base_agent.py`

---

## 5. DATA PIPELINE & CACHING

### Three-Layer Cache Hierarchy

```
L1: Local Cache (backend/data/cache/{date}.parquet)
    ↓ miss or stale (>300s for recent dates)
L2: GCS Live Cache (gs://flowlyte/cache/{date}.parquet)
    ↓ miss
L3: GCS Gold Layer (archival, pre-computed historical)
```

### Full Scan Process

1. **Fetch OHLCV** (async, concurrent): Polygon API — Daily (5500 days), Hourly (200d), 30m (30d), 15m (20d)
2. **Fetch Details**: Market cap, sector, description (cached 7 days)
3. **Fetch Fundamentals**: Polygon + FMP — ratios, estimates, insider trading, price targets
4. **Run Math Tasks**: Parallel ProcessPoolExecutor — per-ticker indicator calculation
5. **Save Cache**: Float64 > Float32 optimization, GCS sync, tier shard merge, Gold promotion

### Tiered Scanning

Universe split into Tier 1 (Mega-cap), Tier 2 (Large-cap), Tier 3 (Mid/Small-cap). Each tier scanned by separate Cloud Run job. Shards merged into unified parquet.

### Scanner Schedule

`backend/scheduler.py` runs every 5 minutes during market hours. `backend/scan_runner.py` for manual/full scans.

### Parquet Schema (Key Columns)

```
Core:        Ticker, Data_Date, Price, Close, Open, High, Low, Volume, Change
Scores:      FT_Score, Trend_Strength, Squeeze, A_Plus_Setup, RS_Score, RS_Change
Volume:      Rel_Vol, Sell_Vol_Pct, Vol_ZScore, FVS_Val, FVS_Pct, FVS_Z_Score
VW Keltner:  VW_KC_Upper, VW_KC_Lower, VW_Divergence
Sequencer:   Seq_Bull_Prep, Seq_Bear_Prep
Timeframes:  FT_Score_W, FT_Score_D, FT_Score_4h, FT_Score_1h, FT_Score_30m (+ squeezes)
Fundamental: TrailingPE, ForwardPE, PEGRatio, PSRatio, PBRatio, EV_EBITDA, ProfitMargin,
             ROE, ROA, RevGrowth, EarnGrowth, DivYield, Beta, ShortPercent
Allocation:  Allocation_Label, Allocation_Action, Allocation_Badge_Color
Sector:      Main_Sector, Sub_Sector
```

---

## 6. TICKER UNIVERSE

**Source**: Supabase `tickers` table (is_active = True)

### Organization
- **ALL_TICKERS**: Full universe (stocks + ETFs + indices)
- **BIG_10**: AAPL, MSFT, NVDA, GOOGL, AMZN, META, TSLA, AVGO, LLY, BRK.B
- **11 GICS Sectors**: XLK, XLF, XLV, XLE, XLC, XLY, XLP, XLI, XLB, XLU, XLRE
- **Industry ETFs**: SMH, IBB, KRE, XRT, ITB, IYT, GDX
- **Commodity ETFs**: GLD, SLV, USO, UNG, DBC
- **Debt ETFs**: TLT, IEF, SHY, HYG, LQD
- **Currency ETFs**: FXE, FXY, DBV
- **Global**: EWJ, EWG, EWU, EEM, ACWI

**Fallback**: Emergency hardcoded list if DB returns < 10 tickers.

---

## 7. SUBSCRIPTION TIERS & FEATURE GATING

### Tiers
- **Free Trial**: Time-limited full access, then restricted
- **Pro**: Full access via Stripe subscription

### Feature Access Map

| Feature Key | Min Tier | Description |
|-------------|----------|-------------|
| `screener.full_filters` | PRO | Advanced screener filters |
| `screener.unlimited_results` | PRO | All results (not just top 10) |
| `breadth.full` | PRO | Full market breadth |
| `macro.full` | PRO | Macro economy analysis |
| `themes.detail` | PRO | Theme deep dive + discovery |
| `squeeze.full` | PRO | Full squeeze radar |
| `portfolio` | PRO | Portfolio analytics |
| `strategy_lab.backtest` | PRO | Backtesting engine |
| `ai.chat` | PRO | Flowlyte AI conversations |
| `ai.unlimited` | PRO | Remove daily AI query limit |
| `options` | PRO | Full options analysis |
| `journal` | PRO | Trading journal |
| `campaigns` | PRO | Strategy campaigns |
| `export.csv` | PRO | CSV export |
| `watchlists.multiple` | PRO | Multiple watchlists |

### Trial Expiry Behavior
- **TrialExpiryModal**: Shown once per session
- **TrialExpiredBanner**: Persistent banner
- **TrialExpiredOverlay**: Blur overlay on all pages except `/dashboard` and `/profile`

---

## 8. FRONTEND ARCHITECTURE

### State Management (React Context)

| Context | Purpose |
|---------|---------|
| **AuthContext** | Supabase session, user role, subscription tier/status, cross-tab sync via BroadcastChannel |
| **MarketContext** | Selected date, inspector ticker, AI modal state, AI context data |
| **ThemeContext** | 13 UI themes, 10 heatmap palettes, CSS variable injection |
| **TierContext** | `hasAccess(featureKey)` checks, trial state calculations |
| **WebSocketContext** | Live ticker updates, scan progress, market scores |
| **JournalContext** | Selected portfolio/account, date range, React Query data |

### API Layer (`src/api/client.ts`)

100+ functions. Base URL: `VITE_API_URL || '/api'`. All requests through centralized client.

### Query Configuration (`src/lib/queryConfig.ts`)

| Stale Time | Duration | Used For |
|------------|----------|----------|
| `realtime` | 15s | Dashboard, portfolio |
| `fast` | 2min | Squeeze radar, ticker tabs |
| `moderate` | 5min | Breadth, themes, pulse |
| `slow` | 10min | Macro, strategy library |
| `static` | 30min | Calendar, earnings |

### Signal Display System

Signals rendered as colored pill badges:
- **Green (opportunity)**: ft_score_high, squeeze_firing, rs_score_high, price_location_high, trend_strength_high, exponential_trend, smart_money_flow, analyst_upside
- **Orange/Red (warning)**: volume_zscore, ft_score_low, rs_score_low, atr_pct_high, rvol_high, short_interest_high, beta_high

Clicking a badge opens the AI panel with signal context.

### Heatmap Coloring

Screener cells use `getHeatmapColor(value, palette)` — maps numeric values to palette colors. 10 palettes: Flowlyte Original, Film Noir, Deep Ocean, Solar Flare, Arctic, Magma, etc.

### Squeeze Dots (Screener Ticker Column)

Multi-timeframe squeeze indicators next to ticker symbol:
- Blue pulsing: Weekly squeeze
- Blue: 2-day squeeze
- Dark blue pulsing: Daily squeeze
- Cyan: 4-hour squeeze

---

## 9. BACKEND ARCHITECTURE

### API Server
- **Framework**: FastAPI (Python 3.12)
- **Port**: 8002
- **CORS**: Configured for frontend origins
- **WebSocket**: `/ws` for live data push (ticker updates, scan progress, market scores)

### Key Backend Modules

| Module | File | Purpose |
|--------|------|---------|
| Aggregator | `backend/logic/aggregator.py` | Central scanner — OHLCV fetch, indicator computation, cache write |
| Score Engine | `backend/logic/score_engine.py` | FT_Score, squeeze, A+ setups |
| Math Worker | `backend/logic/math_worker.py` | All technical indicators (parallel) |
| Data Manager | `backend/logic/data_manager.py` | Async OHLCV from Polygon/FMP |
| Theme Manager | `backend/logic/theme_manager.py` | Static theme-to-ticker mapping |
| Theme Engine | `backend/logic/engines/theme_engine.py` | Dynamic DBSCAN clustering |
| Volume Engine | `backend/logic/engines/volume.py` | FVS, Rel_Vol, Sell_Vol_Pct |
| Trend Engine | `backend/logic/engines/trend.py` | RS_Score |
| ETS Engine | `backend/logic/engines/ets_engine.py` | Exponential Trend Strength |
| Volatility Engine | `backend/logic/engines/volatility.py` | ATR Extension |
| VW Keltner | `backend/logic/vw_keltner.py` | Volume-weighted Keltner channels |
| Sequencer | `backend/logic/sequencer.py` | Wyckoff-inspired setup detection |
| Portfolio | `backend/logic/portfolio.py` | FIFO P&L, holdings, transactions |
| Breadth | `backend/logic/breadth.py` | Market breadth precomputation |
| Macro Data | `backend/logic/macro_data.py` | Cycle detection, signal pairs |
| Daily Briefing | `backend/logic/daily_briefing.py` | AI-generated market summary |
| Alert Manager | `backend/logic/alert_manager.py` | Price/condition alerts |
| Tier Manager | `backend/logic/tier_manager.py` | Subscription tier logic |
| Tickers | `backend/logic/tickers.py` | Ticker universe management |
| GCS Client | `backend/logic/ingestion/gcs_client.py` | Google Cloud Storage (singleton) |
| Polygon Wrapper | `backend/logic/ingestion/polygon_wrapper.py` | Polygon.io API |
| FMP Wrapper | `backend/logic/ingestion/fmp_wrapper.py` | Financial Modeling Prep API |
| Supabase Client | `backend/logic/supabase_client.py` | Shared client (service role key) |

### Alert System

Stored in Supabase `alerts` table. Supports:
- **Scope**: market (all tickers), sector, or specific ticker list
- **Rules**: metric + operator + value (AND/OR logic)
- **Channels**: email, Telegram, Discord
- **Cooldown**: Configurable minutes between triggers

---

## 10. DATABASE & AUTH

- **Supabase** (PostgreSQL + Auth + RLS)
- Backend uses `SUPABASE_SERVICE_ROLE_KEY` (bypasses RLS)
- Frontend uses `VITE_SUPABASE_ANON_KEY` with session tokens
- Migrations in `backend/migrations/`
- Key tables: `profiles`, `tickers`, `alerts`, `portfolios`, `accounts`, `transactions`, `watchlists`, `marketing_content`

---

## 11. MARKETING AGENT

Standalone **CrewAI** pipeline (`marketing-agent/`) that generates marketing content from live Flowlyte data.

**Pipeline**: Data Fetcher > Content Creator > Validation Gate > Supabase
**Anti-hallucination**: Three-layer defense — hardened prompts, CrewAI task guardrail, post-run validation (9 automated checks)
**Content types**: Tweets, blog posts, video transcripts

---

## 12. GLOSSARY OF TERMS

| Term | Meaning |
|------|---------|
| **FT_Score** | Flow/Technical Score — directional momentum per timeframe (-15 to +15) |
| **Trend_Strength** | Aggregate FT_Score across all timeframes (0-100%) |
| **FVS** | Flowlyte Volume Spread — smart money flow detection |
| **FVS_Val** | Raw volume spread value |
| **FVS_Pct** | FVS normalized by price (cross-ticker comparable) |
| **FVS_Z_Score** | Statistical significance of FVS |
| **RS_Score** | Relative Strength vs SPY (-10 to +10) |
| **ETS** | Exponential Trend Strength — composite momentum (0-100) |
| **Squeeze** | Bollinger Bands inside Keltner Channel (volatility compression) |
| **A+ Setup** | Squeeze + extreme FT_Score = highest conviction |
| **ATR Extension** | Distance from EMA21 in ATR units (overextension measure) |
| **Price Location** | Position within 52-week range (0-100%) |
| **Sequencer** | Wyckoff-inspired consecutive bar countdown (perfect at 9) |
| **VW Keltner** | Volume-weighted Keltner Channel with divergence detection |
| **BB_Width** | Bollinger Band width (compression indicator) |
| **Rel_Vol** | Current volume / 50-day average volume |
| **Vol_ZScore** | Volume statistical anomaly (> 2 = significant) |
| **Sell_Vol_Pct** | Percentage of volume attributed to selling |
| **SP Pattern** | Stacked EMA pattern (EMA5 > EMA8 > EMA21 > EMA34) |
| **Supertrend** | Trend-following indicator (+1 up, -1 down) |
| **Sentinel** | AI agent system (LangGraph) |
| **Guardian** | Portfolio risk management agent |
| **Viral Score** | Theme momentum hype level (0-1) |
| **Fracture Risk** | Theme leader concentration risk |
| **Gold Layer** | Archival tier in GCS cache hierarchy |
| **Tier Shard** | Partial scan result (Mega/Large/Mid-Small cap) |

---

## 13. KEY ARCHITECTURAL PATTERNS

1. **Async-First Pipeline**: Concurrent data fetches with semaphore rate limiting
2. **Multi-Tier Caching**: L1 local > L2 GCS live > L3 Gold archival
3. **Process Pooling**: CPU-bound math in separate processes (avoids GIL)
4. **LangGraph Agents**: Supervisor routes to specialized workers
5. **Parquet Format**: Memory-efficient columnar storage for 50+ metrics per ticker
6. **RLS Security**: Row-Level Security on all user data
7. **Precomputation**: L2 analytics computed post-scan, cached in GCS
8. **Graceful Fallbacks**: Manual maps, emergency ticker lists, API retries
9. **Tiered Scanning**: Universe split by market cap for parallel Cloud Run jobs
10. **Cross-Tab Sync**: BroadcastChannel API for auth state across browser tabs
