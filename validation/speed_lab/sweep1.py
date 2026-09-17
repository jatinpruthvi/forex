"""
speed_lab/sweep1.py — is there ANY cost-viable edge on this data?

Sweeps signal family x timeframe x threshold x stop width x target x hold,
per pair, and ranks by NET expectancy (repo cost model, pessimistic exits).

  python3 validation/speed_lab/sweep1.py            # EURUSD scan (~1 min)
  python3 validation/speed_lab/sweep1.py --all      # all 11 pairs (~15 min)
"""
from __future__ import annotations

import sys, time, itertools
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E

TF_MIN = {5: 5, 15: 15, 30: 30, 60: 60, 240: 240}
HOLD_HOURS = 96                     # max hold 4 trading days


def scan(sym: str, source: str, tfs, families, ks, sas, trs, verbose=True):
    rows = []
    for tf in tfs:
        d = E.load_ohlc(sym, tf, source)
        hold = max(8, int(HOLD_HOURS * 60 / tf))
        for fam, k, sa, tr in itertools.product(families, ks, sas, trs):
            if fam not in ("rev", "mom") and k != ks[0]:
                continue          # donchian families ignore k - avoid duplicate work
            kw = dict(k=k, stop_atr=sa, target_r=tr, n_ch=20) if fam in ("rev", "mom") \
                else dict(n_ch=max(6, 240 // tf), stop_atr=sa, target_r=tr)
            s = E.signals(d, sym, fam, **kw)
            if s is None or len(s["idx"]) < 60:
                continue
            r = E.resolve(s, d, max_hold_bars=hold)
            e = E.expectancy(s, r, sym)
            rows.append(dict(sym=sym, tf=tf, fam=fam, k=k, sa=sa, tr=tr, **e))
    return rows


def main():
    all_pairs = "--all" in sys.argv
    syms = E.ALL_PAIRS if all_pairs else ["EURUSD"]
    sources = {"EURUSD": "m5"}
    tfs = [5, 15, 30, 60, 240]
    fams = ["rev", "mom", "don_break", "don_fade"]
    ks = [1.5, 2.0, 2.5, 3.0]
    sas = [1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0]
    trs = [1.0, 1.5, 2.0, 3.0, 4.0]

    t0 = time.time()
    rows = []
    for sym in syms:
        src = "m5"
        rows += scan(sym, src, tfs, fams, ks, sas, trs)
        if True:
            print(f"  {sym}: {len(rows)} configs so far  ({time.time()-t0:.0f}s)", flush=True)

    rows.sort(key=lambda r: -r["e_net"])
    print(f"\nscanned {len(rows)} configs in {time.time()-t0:.0f}s")

    print("\n" + "=" * 108)
    print("TOP 25 BY NET EXPECTANCY (costs ON, pessimistic exits)")
    print("=" * 108)
    hdr = f"{'sym':<8}{'tf':>4}{'fam':<11}{'k/nch':>6}{'SA':>5}{'TR':>5}{'n':>7}{'stopP':>7}{'cost%':>7}{'WR%':>7}{'Egross':>9}{'Enet':>9}{'PF':>6}"
    print(hdr); print("-" * 108)
    for r in rows[:25]:
        print(f"{r['sym']:<8}{r['tf']:>4}{r['fam']:<11}{r['k']:>6.1f}{r['sa']:>5.1f}"
              f"{r['tr']:>5.1f}{r['n']:>7}{r['med_stop']:>7.2f}{r['cost_R']*100:>7.1f}"
              f"{r['wr']*100:>7.1f}{r['e_gross']:>+9.4f}{r['e_net']:>+9.4f}{r['pf']:>6.2f}")

    pos = [r for r in rows if r["e_net"] > 0]
    print(f"\nconfigs with NET expectancy > 0 : {len(pos)} / {len(rows)} "
          f"({len(pos)/max(len(rows),1)*100:.1f}%)")
    for thr in (0.05, 0.10, 0.15, 0.20):
        c = [r for r in rows if r["e_net"] >= thr]
        print(f"  E_net >= {thr:+.2f}R : {len(c):>5}"
              + (f"   best: {max(c, key=lambda r: r['n'])['sym']} tf{max(c, key=lambda r: r['n'])['tf']} {max(c, key=lambda r: r['n'])['fam']} n={max(c, key=lambda r: r['n'])['n']}" if c else ""))

    print("\n" + "=" * 108)
    print("BEST BY TIMEFRAME (max E_net with n >= 200 trades)")
    print("=" * 108)
    for tf in tfs:
        sub = [r for r in rows if r["tf"] == tf and r["n"] >= 200]
        if not sub: continue
        b = max(sub, key=lambda r: r["e_net"])
        print(f"  M{tf:<4} {b['sym']:<7}{b['fam']:<11}k={b['k']:<4}SA={b['sa']:<5}TR={b['tr']:<5}"
              f"n={b['n']:<6}stop={b['med_stop']:6.2f}p cost={b['cost_R']*100:5.1f}% "
              f"Eg={b['e_gross']:+.4f} En={b['e_net']:+.4f} PF={b['pf']:.2f}")

    print("\n" + "=" * 108)
    print("BEST GROSS EDGE PER FAMILY (is the raw signal real, ignoring cost?)")
    print("=" * 108)
    for fam in fams:
        sub = [r for r in rows if r["fam"] == fam and r["n"] >= 200]
        if not sub: continue
        b = max(sub, key=lambda r: r["e_gross"])
        print(f"  {fam:<11} best E_gross {b['e_gross']:+.4f}R  "
              f"({b['sym']} M{b['tf']} k={b['k']} SA={b['sa']} TR={b['tr']} n={b['n']} "
              f"stop={b['med_stop']:.2f}p cost={b['cost_R']*100:.1f}% -> E_net {b['e_net']:+.4f}R)")

    np.save(Path("/tmp/speedlab_cache/sweep1.npy"),
            np.array([[r.get("k", 0), r.get("sa", 0), r.get("tr", 0), r["tf"],
                       r["n"], r["e_gross"], r["e_net"], r["cost_R"], r["wr"],
                       r["med_stop"], r["pf"]] for r in rows]))
    import json
    Path("/tmp/speedlab_cache/sweep1.json").write_text(json.dumps(rows))


if __name__ == "__main__":
    main()
