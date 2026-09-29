# MQL5 Pro — Agentic Skill for Production-Grade MetaTrader 5 Development

A comprehensive, battle-tested Claude Skill for **AI-assisted MQL5 development** — Expert Advisors, custom indicators, GUI panels, Pine Script conversion, and Strategy Tester automation.

This skill acts as a strict syntactical and architectural reference designed to prevent AI hallucinations, enforce correct MQL5 patterns, and produce compile-clean, production-ready code on current MetaTrader 5 builds (5800+). Every rule in it was verified against the official MQL5 reference or a real compile — including a built-in **self-correction protocol** that forces the AI to fix the skill itself whenever a defect in its knowledge is proven.

Compatible with: **Claude.ai** (upload as `.skill`), **Claude Code** (copy to skills directory), and any LLM tool that consumes Markdown skill files.

## 📁 Repository Structure

```
mql5-pro/
├── SKILL.md                        # Entry point — routing table, language model, deliverable checklist
├── references/                     # Task-specific deep references (loaded on demand)
│   ├── trading.md
│   ├── indicators.md
│   ├── gui.md
│   ├── advanced.md
│   ├── pitfalls.md
│   ├── testing.md
│   ├── pine-to-mql5.md
│   └── module-integration.md
└── assets/                         # Templates + curated MT5 standard-library slice
    ├── EA_Template.mq5
    ├── Indicator_Template.mq5
    ├── Panel_Template.mq5
    ├── Controls/  Canvas/  ChartObjects/  Charts/  Trade/  Files/  Tools/
```

The skill uses **progressive disclosure**: only `SKILL.md` loads into context; the AI reads the relevant reference file per task. This keeps token cost minimal while covering the full MQL5 surface.

## 🧠 Reference Modules

- [**Trading Operations**](mql5-pro/references/trading.md)
  * **Purpose:** Production-grade order and position management.
  * **Key Concepts:** CTrade correct configuration, manual `MqlTradeRequest` + full retcode handling, volume/price normalization (tick-size rounding — not `NormalizeDouble`), `STOPS_LEVEL`/`FREEZE_LEVEL` validation, risk-based position sizing, `OnTradeTransaction` reliable event detection, trailing stops, **funded/prop-firm account protection** (daily/total drawdown kill-switch).

- [**Custom Indicators**](mql5-pro/references/indicators.md)
  * **Purpose:** Buffer-correct, non-repainting indicator construction.
  * **Key Concepts:** `OnCalculate`/`prev_calculated` loop discipline, handle lifecycle (OnInit only), multi-timeframe/multi-symbol data synchronization, **ICT/SMC detection** (FVG, Order Blocks, BOS/ChoCh, liquidity sweeps, premium/discount zones).

- [**GUI & Dashboards**](mql5-pro/references/gui.md)
  * **Purpose:** Panels, buttons, and on-chart drawing without visual drift.
  * **Key Concepts:** `CAppDialog` architecture, `CCanvas` rendering, THEME color + METRICS dimension libraries (zero raw literals), coordinate systems, `OnChartEvent` routing, dark-theme bitmap limitations of the standard Controls library.

- [**Advanced Patterns**](mql5-pro/references/advanced.md)
  * **Purpose:** Infrastructure beyond basic EAs.
  * **Key Concepts:** `CArrayObj` collections for grid/hedging sets, `OnTimer` state machines (the correct replacement for `Sleep`), `WebRequest` + JSON builder/extractor, sockets, ONNX inference, settings persistence, multi-symbol EA architecture, account-based licensing.

- [**Pitfalls & Error Reference**](mql5-pro/references/pitfalls.md)
  * **Purpose:** The traps that break generated MQL5 code — compile-time, runtime, and tester.
  * **Key Concepts:** MQL4 contamination scan + conversion table, runtime error-code table (4806, 10016, 10025 …), `TimeCurrent()` stall vs `GetTickCount()`, MQL5 Market automatic-validation checklist, performance tuning, **autonomous MT5 log reading** (UTF-16LE parsing for agentic workflows).

- [**Strategy Tester & Optimization**](mql5-pro/references/testing.md)
  * **Purpose:** Testing methodology, not just tester mechanics.
  * **Key Concepts:** Modeling-mode selection matrix, backtest validity requirements, full `TesterStatistics` table, walk-forward analysis (native MT5 Forward), plateau-based parameter selection, frames-based Monte Carlo, **headless compile + backtest automation** via `metaeditor64.exe /compile` and `terminal64.exe /config:tester.ini`.

- [**Pine Script → MQL5 Conversion**](mql5-pro/references/pine-to-mql5.md)
  * **Purpose:** Deterministic conversion of TradingView Pine Script (v4–v6) indicators and strategies to MQL5 with a verified 1:1 mathematical match.
  * **Key Concepts:** The golden execution-model mapping (Pine script body = `OnCalculate` loop body), bar-indexing translation, `na` → `EMPTY_VALUE` semantics, `var`/`varip` state replication, full `ta.*` mapping table with **formula-mismatch flags** (Pine MACD signal = EMA vs `iMACD` = SMA), `request.security` → non-repainting MTF (shift + 1 rule), `strategy.*` → `CTrade`, timezone re-anchoring, and a **mandatory value-verification protocol**.

- [**Module Integration**](mql5-pro/references/module-integration.md)
  * **Purpose:** Rules applied only when a program will later be merged with other EAs/indicators/panels.
  * **Key Concepts:** Per-module STATE structs, manifest headers, namespaced inputs/magic/objects, single-handler dispatch, indicator buffer offsets.

## 🗃️ Templates & Bundled Standard Library (`/assets`)

Three ready-made templates are the mandatory starting point — never a blank file:

| Template | Base for |
|---|---|
| `EA_Template.mq5` | Any EA: new-bar gating, ATR-based SL/TP, risk-sized lots, margin pre-check, retry loop, `OnTradeTransaction`, `OnTester` criterion |
| `Indicator_Template.mq5` | Any indicator: correct `prev_calculated` loop, color line + arrow signals, non-repaint placement, warm-up handling |
| `Panel_Template.mq5` | Any GUI panel: THEME/METRICS libraries, factories, layout grid, event routing, full cleanup |

`assets/` also ships a curated slice of the MetaTrader 5 standard Include tree (Controls, Canvas, ChartObjects, Trade, Files) serving as the **authoritative local API reference** — the AI reads the actual class headers instead of guessing signatures.

## 🚀 Installation

**Claude.ai (web/app):** Settings → Capabilities → Skills → upload `mql5-pro_vXX.skill` (the release ZIP). Done — it triggers automatically on any MQL5/MT5 task.

**Claude Code:**
```bash
git clone https://github.com/YOUR_USERNAME/mql5-pro-skill.git
cp -r mql5-pro-skill/mql5-pro ~/.claude/skills/
```

**Other LLM tools:** feed `SKILL.md` as a system prompt / custom instruction and attach the relevant `references/*.md` per task.

## 🤖 Directives for AI Agents

**MANDATORY PROTOCOL** — before generating any MQL5 solution:

1. **Route through `SKILL.md`:** read the reference file(s) matching the task from the routing table. For an EA with a panel, read `trading.md` + `gui.md` and merge the corresponding templates.
2. **Verify against the bundled headers:** any standard-library API (CTrade methods, Controls setters, `CONTROLS_*` constants) is confirmed in `assets/` — a real header beats memory.
3. **Compile when possible:** with local tooling, run `metaeditor64.exe /compile:"file.mq5" /log`, parse the UTF-16LE log, fix, recompile. Never deliver uncompiled code when a compiler is reachable.
4. **Self-correct:** if a failure is traced to wrong information **in the skill itself**, fix the skill file immediately, verify the correction against an authoritative source, and run the whole-skill consistency check — per the governing rule in `SKILL.md`.
5. **Deliverable checklist:** run the 12-point checklist at the end of `SKILL.md` (MQL4 contamination scan, zero warnings, normalized volumes/prices, validated stops, cleanup in `OnDeinit`, mental compile pass) before handing over code.

## 🔌 Recommended Companion Tooling

| Tool | Role |
|---|---|
| [MQL5 Help MCP](https://mcpmarket.com/server/mql5-help) | Instant query over 4500+ official MQL5 docs — API verification |
| [mcp-metatrader5-server](https://github.com/Qoyyuum/mcp-metatrader5-server) | Live terminal bridge: market data, symbol specs, demo-account execution |
| `metaeditor64.exe /compile` | Headless compile loop |
| `terminal64.exe /config:tester.ini` | Headless backtests and optimization (recipe in `references/testing.md` §9) |

## ⚖️ Notice

The files under `assets/` that mirror the MetaTrader 5 standard Include tree are © MetaQuotes Ltd and ship with every MetaTrader 5 installation; they are bundled here unmodified, solely as a local API reference for code verification. All original skill content (SKILL.md, references, templates) is provided as-is, without warranty. Trading involves substantial risk — test everything on a demo account first.
