# ChartFanatics EAs

Expert Advisors built from the ChartFanatics playbooks archived in this folder. One `.mq5` per
strategy, each wired into the repository's shared engine (`MQL5_Master/Include/EACommon.mqh`), each
with its own magic number, and each traceable back to its work card in
[`../todos/`](../todos/).

**Status: static-checked, not yet compiled.** `python3 scripts/check_mql5_source.py
chartfanatics/mql5-eas/*.mq5` reports 0 findings (contract: `CEAStrategy` subclass, unique magic,
engine delegation, no MQL4 contamination, declared identifiers, balanced blocks). Nothing here has
been through MetaEditor yet — that is Stage 0 of
[`docs/EA_VALIDATION_PLAYBOOK.md`](../../docs/EA_VALIDATION_PLAYBOOK.md) and the first thing to run
on the Windows machine.

## Wave 1

| Card | Strategy | EA | Magic | TF | Reads from the engine |
|---|---|---|---|---|---|
| [#04](../todos/amd-model.md) | AMD Model | `EA_CF_AMD_Model.mq5` | 3201 | M5 | `SigSweepReclaim` + `SigEmaCascade`, playbook macro windows (09:50–10:10 / 10:50–11:10 ET), 2 trades/day, two-loss day lock |
| [#26](../todos/structure-ote.md) | Structure + OTE | `EA_CF_Structure_OTE.mq5` | 3202 | M15 | `SigOrderBlockRetest` (POI) + breaker fallback, **first premium/discount + OTE (62–79%) implementation in the repo** |
| [#23](../todos/smt-divergence-po3.md) | SMT Divergence + PO3 | `EA_CF_SMT_PO3.mq5` | 3203 | M5 | `SigSweepReclaim` + direct symbol-vs-symbol SMT divergence (NQ vs ES) and the 50%-level target |
| [#22](../todos/po3-ote-adr.md) | PO3, OTE + ADR | `EA_CF_PO3_OTE_ADR.mq5` | 3204 | M15 | PD-array proximity, daily bias, ADR budget, **fib-anchored OTE limit** (stop 1.0 fib, target 0.0 fib → fixed R by geometry) |
| [#07](../todos/break-retest.md) | Break & Retest | `EA_CF_Break_Retest.mq5` | 3205 | M5 | `SigBreakRetest` + rejection-wick confirmation + no-trade-zone gate |
| [#12](../todos/intraday-liquidity-volatility-model.md) | Intraday Liquidity & Volatility | `EA_CF_Intraday_Liquidity.mq5` | 3206 | M5 | failed-raid detector over PDH/PDL, Asian and London extremes + `SigFvgRetest` (MSS fallback), NY window |

Magic block **3201–3247** is reserved for this family (one per card). `manifest.json` is the
machine-readable source of truth and is read by [`../gen_todos.py`](../gen_todos.py) to fill each
card's Tracking block.

## Deploy

Each EA includes `..\..\Include\EACommon.mqh`, so the folder has to sit at
`MQL5\Experts\chartfanatics\`:

```powershell
# copy the family into the terminal
$dst = "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Experts\chartfanatics"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item chartfanatics\mql5-eas\*.mq5 $dst

# the shared headers must be in MQL5\Include\ (the 65 EAs need them too)
Copy-Item MQL5_Master\Include\*.mqh "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Include\"
```

Then compile everything, including this family, with the harness:

```powershell
.\validation\mt5_harness\compile_all.ps1 -Mql5 "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5"
```

`compile_all.ps1` picks up `Experts\chartfanatics\*.mq5` automatically; an EA that fails to compile
produces no result row in the tester sweep that follows.

## Known gaps (do not paper over these)

* **Never compiled.** Static checks are not a compiler.
* **Symbol universes are broker-dependent.** The defaults assume the names this repository already
  uses elsewhere (`US100`, `US500`, `GER40`); other brokers call NQ `NAS100`/`USTEC`. The engine
  logs and skips symbols the broker does not offer — check the Experts log after first run.
* **SMT needs its twin.** `EA_CF_SMT_PO3` compares `InpSymbolsToTrade` with `InpSmtSymbol`
  (default `US500` for a `US100` leg). Without that symbol the divergence gate fails open by
  default and logs loudly; `InpSmtFailClosed=true` refuses to trade instead.
* **News-day quality is not encoded.** The AMD playbook's "high probability day" filter is a
  calendar decision (CPI/NFP/FOMC days) and the repo's calendar is tester-incomplete; the news
  filter is therefore off.
* **Scale-in rules are off.** The PO3/AMD models scale only once the first entry is at break-even;
  the engine holds one position per symbol, so those additions are not implemented.

Next waves: cards with no EA yet are listed on [`../TODO.md`](../TODO.md) — a card gets an EA entry
here once its source rules are read and mapped, never before.
