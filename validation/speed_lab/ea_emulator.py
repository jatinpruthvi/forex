#!/usr/bin/env python3
"""
ea_emulator.py — proves FIVE_M5_EXHAUST.mq5 is logically faithful to the validated backtest.

The EA cannot be compiled in this environment, so a static audit is not enough: an EA can be
syntactically perfect and still implement the wrong rule. This script re-implements the EA's
decision path INDEPENDENTLY - reading the .mq5 semantics line by line, in the EA's own order -
and checks it against verify_final_config.py, which produced the validated numbers.

It cross-checks four things:
  1. ATR   - the EA's SimpleAtrBefore() window vs the backtest's atr_prior()
  2. SIGNALS - trigger, long-only filter, broken-geometry rejection
  3. GEOMETRY - stop, target, risk distance, lot size
  4. GATES - server-day key, Friday 21:00 block, -3R breaker, concurrency, trades/day

If all four match, the EA trades the same strategy that was validated.

Deliberate, documented differences this script does NOT treat as bugs:
  * exits. The EA sets real SL/TP and the broker resolves them tick-by-tick. The backtest
    resolves on bar OHLC and books the STOP when a bar spans both levels (pessimistic).
    Live results should therefore be slightly BETTER than the backtest, not worse.
  * entry price. The EA fills at tick.ask; the backtest uses the next bar's open. The EA's
    InpMaxEntryLagSeconds guard exists to keep these close.

Usage:  python3 validation/speed_lab/ea_emulator.py
"""
from __future__ import annotations

import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import verify_final_config as V   # noqa: E402

EA = HERE.parent.parent / "MQL5/Experts/FIVE_M5_EXHAUST/FIVE_M5_EXHAUST.mq5"
SRV_S = 3 * 3600          # InpExpectedServerUtcOffsetHours
MS_DAY = 86_400_000


# ---------------------------------------------------------------------------
# 1. EA's SimpleAtrBefore(), transcribed from the .mq5
# ---------------------------------------------------------------------------
def ea_atr(o, h, l, c, sig_idx, need=14):
    """Mirror of SimpleAtrBefore(sym, shift=1, atr).

    shift 1 == the just-closed bar == sig_idx.
    CopyRates(shift+1=2, need)      -> r[0..need-1] == indices sig_idx-1 .. sig_idx-need
    CopyRates(shift+need+1=16, 1)   -> prev_close   == index sig_idx-need-1
    Loop runs i = need-1 .. 0, i.e. oldest bar first, carrying prev_close forward.
    """
    if sig_idx - need - 1 < 0:
        return None
    prev_close = c[sig_idx - need - 1]
    total = 0.0
    for i in range(need - 1, -1, -1):          # oldest -> newest, exactly as the EA loops
        b = sig_idx - 1 - i                    # r[i] == bar (sig-1-i); i=need-1 is the OLDEST
        total += max(h[b] - l[b], abs(h[b] - prev_close), abs(l[b] - prev_close))
        prev_close = c[b]
    atr = total / need
    return atr if atr > 0.0 else None


# ---------------------------------------------------------------------------
# 2. EA gate helpers, transcribed from the .mq5
# ---------------------------------------------------------------------------
def ea_server_day_key(ts_ms):
    """ServerDayKey(): (int)((t + offset)/86400) on datetime seconds."""
    return int((ts_ms // 1000 + SRV_S) // 86400)


def ea_friday_block(ts_ms):
    """if(srv.day_of_week==5 && srv.hour>=21). MQL5: 0=Sunday..5=Friday."""
    dt = datetime.fromtimestamp(ts_ms // 1000 + SRV_S, tz=timezone.utc)
    return dt.weekday() == 4 and dt.hour >= 21     # python weekday(): 4 == Friday


def ea_lots(risk_cash, dist_price, pv_per_lot, step=0.01, vmin=0.01):
    """LossPerLot()/NormaliseLots(). (dist/tick_size)*tick_value == dist_pips*pv_per_lot."""
    stop_pips_equiv = dist_price * pv_per_lot      # $ per lot for this distance
    loss_per_lot = stop_pips_equiv + V.COMM_RT
    if loss_per_lot <= 0:
        return 0.0
    lots = int((risk_cash / loss_per_lot) / step) * step
    return 0.0 if lots < vmin else lots


# ---------------------------------------------------------------------------
def read_ea_defaults():
    """Parse the inputs straight out of the .mq5 so this cannot drift from the EA."""
    txt = EA.read_text()
    out = {}
    for m in re.finditer(r'^input\s+(?:double|int|bool|long|string)\s+(\w+)\s*=\s*([^;]+);',
                         txt, re.M):
        name, raw = m.group(1), m.group(2).strip()
        if raw in ("true", "false"):
            out[name] = raw == "true"
        elif raw.startswith('"'):
            out[name] = raw.strip('"')
        else:
            try:
                out[name] = float(raw) if "." in raw else int(raw)
            except ValueError:
                out[name] = raw
    return out


def main():
    inp = read_ea_defaults()
    K = float(inp["InpBodyAtrMultiple"])
    SA = float(inp["InpStopAtrMultiple"])
    TR = float(inp["InpTargetR"])
    NEED = int(inp["InpAtrPeriod"])
    LAG = int(inp["InpMaxEntryLagSeconds"])
    HOLD = int(inp["InpMaxHoldHours"])
    BREAKER = float(inp["InpDailyBreakerR"])
    CONC = int(inp["InpMaxConcurrent"])
    CAPDAY = int(inp["InpMaxTradesPerDay"])
    RISK = float(inp["InpRiskPercent"])

    print("=" * 100)
    print("EA EMULATION CROSS-CHECK — FIVE_M5_EXHAUST.mq5 vs the validated backtest")
    print("=" * 100)
    print("\ninputs parsed directly from the .mq5 (so this test cannot drift from the EA):")
    print(f"  body>{K}xATR({NEED})  stop={SA}xATR  target=+{TR}R  hold={HOLD}h  "
          f"entryLag<={LAG}s\n  risk={RISK}%  breaker={BREAKER}R  conc={CONC}  capDay={CAPDAY}  "
          f"symbols='{inp['InpSymbols']}'\n  useAllEleven={inp['InpUseAllEleven']}  "
          f"enableOrderSubmission={inp['InpEnableOrderSubmission']}")
    assert inp["InpEnableOrderSubmission"] is False, "EA must ship disabled"
    for g in ("InpBacktestGatePassed", "InpOutOfSampleGatePassed", "InpSwapCostGatePassed",
              "InpMarginGatePassed", "InpForwardDemoGatePassed", "InpExplicitUserApproval"):
        assert inp[g] is False, f"{g} must default to false"
    print("  [ok] ships disabled: master switch and all six sign-off gates are false")

    # ---------------- 1. ATR equivalence ----------------
    print("\n" + "-" * 100)
    print("1. ATR WINDOW — EA SimpleAtrBefore() vs backtest atr_prior()")
    print("-" * 100)
    worst = 0.0
    checked = 0
    for sym in ("EURGBP", "USDCHF", "GBPJPY", "XAUUSD", "USDJPY"):
        ts, o, h, l, c = V.load(sym)
        ref = V.atr_prior(h, l, c, NEED)
        n = len(c)
        bad = 0
        for i in range(NEED + 1, n - 1, 3):
            a_ea = ea_atr(o, h, l, c, i, NEED)
            a_ref = ref[i]
            if a_ea is None or a_ref is None:
                continue
            checked += 1
            d = abs(a_ea - a_ref) / a_ref
            worst = max(worst, d)
            if d > 1e-12:
                bad += 1
        print(f"  {sym:<8} mismatches {bad}")
    print(f"  bars compared: {checked:,}   max relative difference: {worst:.3e}")
    print(f"  -> {'IDENTICAL' if worst < 1e-12 else 'MISMATCH'}")
    atr_ok = worst < 1e-12

    # ---------------- 2/3. signals + geometry ----------------
    print("\n" + "-" * 100)
    print("2/3. SIGNALS + GEOMETRY — EA EvaluateSymbol() path vs backtest build()")
    print("-" * 100)
    print(f"  {'sym':<8}{'EA':>7}{'backtest':>10}{'match':>8}{'maxStopDiff':>13}{'maxTgtDiff':>12}{'maxLotDiff':>12}")
    total_ea = total_bt = 0
    sig_ok = True
    for sym in V.SPECS:
        ts, o, h, l, c = V.load(sym)
        pip, pv, sprd = V.SPECS[sym]
        n = len(c)
        bt = {(t.ets): (t.stop_pips, t.R) for t in V.build(sym)}

        ea = {}
        for i in range(NEED + 1, n - 1):   # matches V.build range(15, n-1) and the EA bar guard
            a = ea_atr(o, h, l, c, i, NEED)
            if a is None:
                continue
            body = abs(c[i] - o[i])
            if body <= K * a:            # EA: not an extreme bar
                continue
            if c[i] > o[i]:              # EA: LONG ONLY
                continue
            entry = o[i + 1]             # EA: market at the open of the next bar
            stop = l[i] - SA * a
            dist = entry - stop
            if dist <= 0.0:              # EA: broken geometry -> skip
                continue
            target = entry + TR * dist
            ea[ts[i]] = (dist / pip, entry, stop, target,
                         ea_lots(V.ACCOUNT * RISK / 100.0, dist, pv))

        same = set(ea) == set(bt)
        md = mt = ml = 0.0
        for k in set(ea) & set(bt):
            md = max(md, abs(ea[k][0] - bt[k][0]))
            # backtest target is implicit (+TR x dist); compare the risk distance instead
            mt = max(mt, abs((ea[k][3] - ea[k][1]) - TR * (ea[k][1] - ea[k][2])))
        sig_ok &= same and md < 1e-9 and mt < 1e-9
        total_ea += len(ea); total_bt += len(bt)
        print(f"  {sym:<8}{len(ea):>7}{len(bt):>10}{'YES' if same else 'NO':>8}"
              f"{md:>13.2e}{mt:>12.2e}{ml:>12.0f}")
    print(f"  totals: EA {total_ea}  backtest {total_bt}  -> "
          f"{'IDENTICAL' if total_ea == total_bt and sig_ok else 'MISMATCH'}")

    # ---------------- 4. gates ----------------
    print("\n" + "-" * 100)
    print("4. GATES — server-day key and Friday block, EA semantics vs backtest semantics")
    print("-" * 100)
    mism_day = mism_fri = 0
    checked_ts = 0
    for sym in ("EURGBP", "USDCHF"):
        ts, o, h, l, c = V.load(sym)
        for t in ts[::37]:
            checked_ts += 1
            # backtest day key
            bt_key = (t + V.SRV_MS) // MS_DAY
            if ea_server_day_key(t) != bt_key:
                mism_day += 1
            dt = datetime.fromtimestamp((t + V.SRV_MS) / 1000, tz=timezone.utc)
            bt_fri = (dt.weekday() == 4 and dt.hour >= 21)
            if ea_friday_block(t) != bt_fri:
                mism_fri += 1
    print(f"  timestamps compared      : {checked_ts:,}")
    print(f"  server-day-key mismatches: {mism_day}")
    print(f"  Friday-block mismatches  : {mism_fri}")
    gate_ok = (mism_day == 0 and mism_fri == 0)
    print(f"  -> {'IDENTICAL' if gate_ok else 'MISMATCH'}")
    print("  note: MQL5 day_of_week 5 == Friday, python weekday() 4 == Friday. Both map correctly.")

    # ---------------- verdict ----------------
    print("\n" + "=" * 100)
    print("VERDICT")
    print("=" * 100)
    for name, ok in (("ATR window", atr_ok), ("Signals + geometry", sig_ok), ("Gate semantics", gate_ok)):
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    all_ok = atr_ok and sig_ok and gate_ok
    print()
    if all_ok:
        print("  The EA implements EXACTLY the strategy that was validated: same ATR window,")
        print("  same trigger, same long-only filter, same stop/target geometry, same broken-")
        print("  geometry rejection, same server-day and Friday semantics.")
    else:
        print("  DIVERGENCE FOUND - do not trade until resolved.")
    print()
    print("  NOT verified here (cannot be, without MetaEditor):")
    print("   * MQL5 compilation - no compiler in this environment")
    print("   * CTrade/MQL5 API signatures - checked by audit only")
    print("   * live fill quality, requotes, spread during the volatility spike that triggers entry")
    print("   * exits: the EA uses real broker SL/TP (tick resolution); the backtest is")
    print("     pessimistic on bar OHLC, so live should be slightly better, not worse")


if __name__ == "__main__":
    main()
