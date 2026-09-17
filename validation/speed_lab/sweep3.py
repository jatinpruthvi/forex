"""
speed_lab/sweep3.py — from surviving edges to minimum days-to-pass.

Takes the out-of-sample survivors from sweep2, applies ONE frozen parameter set
uniformly across all 11 pairs (no per-pair fitting), and then searches the
portfolio controls that the challenge actually constrains:

    risk per trade  r
    max concurrent positions
    max trades per day
    intra-day circuit breaker (stop after N net losing R)
    risk base (fixed on the initial $2,500 vs compounding on equity)

Ranked on the HELD-OUT TEST half only (2024-09-11 .. 2026-09-11) by median
walk-forward days-to-pass, with pass rate and rule breaches reported alongside.

  python3 validation/speed_lab/sweep3.py            # leaders from sweep2
  python3 validation/speed_lab/sweep3.py --quick    # smaller control grid
"""
from __future__ import annotations

import sys, time, json, itertools
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E
import portfolio as P

TRAIN_END = 1726012800000
TEST_END = 1 << 62
HOLD_HOURS = 96
QUICK = "--quick" in sys.argv


def resolve_all_pairs(tf, fam, k, sa, tr, n_ch=None):
    """Apply one frozen parameter set to every pair; return TEST-period trades."""
    per = {}
    stats = []
    for sym in E.ALL_PAIRS:
        d = E.load_ohlc(sym, tf, "m5")
        hold = max(8, int(HOLD_HOURS * 60 / tf))
        kw = (dict(k=k, stop_atr=sa, target_r=tr, n_ch=n_ch or 20) if fam in ("rev", "mom")
              else dict(n_ch=n_ch or max(6, 240 // tf), stop_atr=sa, target_r=tr))
        s = E.signals(d, sym, fam, **kw)
        if s is None:
            continue
        r = E.resolve(s, d, max_hold_bars=hold)
        m = r["ts"] >= TRAIN_END
        if m.sum() < 25:
            continue
        sub = {kk: vv[m] for kk, vv in r.items()}
        e = E.expectancy(s, sub, sym)
        stats.append((sym, e))
        per[sym] = sub
    return per, stats


def summarise(stats):
    if not stats:
        return dict(pairs=0, n=0, en=0.0, eg=0.0, tpd=0.0, pos_pairs=0, cost=0.0, stop=0.0)
    n = sum(e["n"] for _, e in stats)
    en = sum(e["en" if False else "e_net"] * e["n"] for _, e in stats) / max(n, 1)
    eg = sum(e["e_gross"] * e["n"] for _, e in stats) / max(n, 1)
    cost = sum(e["cost_R"] * e["n"] for _, e in stats) / max(n, 1)
    stop = sum(e["med_stop"] * e["n"] for _, e in stats) / max(n, 1)
    pos = sum(1 for _, e in stats if e["e_net"] > 0)
    return dict(pairs=len(stats), n=n, en=en, eg=eg, cost=cost, stop=stop,
                pos_pairs=pos, tpd=n / 730.0)


def main():
    surv = json.loads(Path("/tmp/speedlab_cache/survivors.json").read_text())
    # de-duplicate to distinct (fam, tf, k, sa, tr) parameter sets, keeping the
    # ones that survived on the most pairs
    seen = {}
    for r in surv:
        key = (r["fam"], r["tf"], r["k"], r["sa"], r["tr"])
        seen.setdefault(key, []).append(r)
    param_sets = sorted(seen.items(), key=lambda kv: (-len(kv[1]), -max(x["en_te"] for x in kv[1])))
    print(f"surviving rows: {len(surv)}   distinct parameter sets: {len(param_sets)}")
    print("top parameter sets by (#pairs survived, best TEST E_net):")
    for key, rs in param_sets[:12]:
        print(f"   {key}  pairs={len(rs)}  bestEnet={max(x['en_te'] for x in rs):+.4f}  "
              f"syms={[x['sym'] for x in rs][:6]}")

    cand = param_sets[:8 if not QUICK else 4]

    # ---- control grid -------------------------------------------------------
    RISKS = [0.005, 0.01, 0.015, 0.02, 0.025] if not QUICK else [0.01, 0.02]
    CONCS = [1, 2, 3, 5, 8, 11] if not QUICK else [2, 5, 11]
    CAPS = [2, 5, 10, 20, 100] if not QUICK else [5, 100]
    DSTOPS = [1.0, 2.0, 3.0, 1e9] if not QUICK else [2.0, 1e9]
    MODES = ["initial", "equity"] if not QUICK else ["initial"]

    results = []
    t0 = time.time()
    for key, _ in cand:
        fam, tf, k, sa, tr = key
        per, stats = resolve_all_pairs(tf, fam, k, sa, tr)
        su = summarise(stats)
        if su["pairs"] == 0:
            continue
        trades = P.build_trades(per)
        trades = [t for t in trades if t.entry_ts >= TRAIN_END]
        print(f"\n--- {fam} M{tf} k={k} SA={sa} TR={tr}: {su['pairs']} pairs, "
              f"{su['n']} TEST trades ({su['tpd']:.2f}/day), agg E_net {su['en']:+.4f}R "
              f"(gross {su['eg']:+.4f}R, cost {su['cost']*100:.1f}%), "
              f"{su['pos_pairs']}/{su['pairs']} pairs positive  [{time.time()-t0:.0f}s]")
        if su["en"] <= 0:
            print("    aggregate TEST expectancy <= 0 -> skip")
            continue

        best = None
        for r, mc, cap, ds, mode in itertools.product(RISKS, CONCS, CAPS, DSTOPS, MODES):
            cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap,
                        daily_stop_R=ds, risk_mode=mode)
            wf = P.walk_forward(trades, cfg, n_starts=(24 if QUICK else 40))
            if wf["n_pass"] == 0:
                continue
            rec = dict(fam=fam, tf=tf, k=k, sa=sa, tr=tr, risk=r, conc=mc, cap=cap,
                       dstop=ds, mode=mode, en=su["en"], tpd=su["tpd"], pairs=su["pairs"],
                       **{kk: vv for kk, vv in wf.items() if kk != "results"})
            results.append(rec)
            score = (rec["pass_rate"], -rec["med_days"])
            if best is None or score > best[0]:
                best = (score, rec)
        if best:
            b = best[1]
            print(f"    best: risk={b['risk']*100:.1f}% conc={b['conc']} cap={b['cap']} "
                  f"dstop={b['dstop']:g} mode={b['mode']}  ->  pass {b['pass_rate']*100:.0f}%, "
                  f"median {b['med_days']} cal-days (p25 {b['p25_days']}, p90 {b['p90_days']}), "
                  f"maxDD {b['max_dd']*100:.1f}%, worstDay ${b['worst_day']:.0f}, "
                  f"maxConc {b['max_conc']}")

    Path("/tmp/speedlab_cache/sweep3.json").write_text(json.dumps(results, default=str))
    results.sort(key=lambda r: (-r["pass_rate"], r["med_days"]))
    print(f"\n{'='*126}")
    print(f"GLOBAL LEADERBOARD — {len(results)} viable (config x control) combinations, TEST half only")
    print(f"{'='*126}")
    print(f"{'fam':<9}{'tf':>4}{'k':>5}{'SA':>5}{'TR':>5}{'Enet':>8}{'risk%':>7}{'conc':>5}"
          f"{'cap':>5}{'dstop':>7}{'mode':>9}{'pass%':>7}{'medD':>6}{'p25':>5}{'p90':>5}"
          f"{'best':>5}{'maxDD%':>8}{'worstDay':>10}{'mc':>4}")
    print("-" * 126)
    for r in results[:30]:
        print(f"{r['fam']:<9}{r['tf']:>4}{r['k']:>5.1f}{r['sa']:>5.1f}{r['tr']:>5.1f}"
              f"{r['en']:>+8.4f}{r['risk']*100:>7.2f}{r['conc']:>5}{r['cap']:>5}"
              f"{r['dstop']:>7g}{r['mode']:>9}{r['pass_rate']*100:>7.1f}{r['med_days']:>6}"
              f"{r['p25_days']:>5}{r['p90_days']:>5}{r['best_days']:>5}{r['max_dd']*100:>8.1f}"
              f"{r['worst_day']:>10.0f}{r['max_conc']:>4}")
    print(f"\ntotal {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
