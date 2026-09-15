"""
speed_lab/sweep2.py — all-pairs, out-of-sample screened search.

PR #9's fatal methodological error was picking the fastest config over the whole
2-year set. This sweep does it properly:

  TRAIN = 2022-09-11 .. 2024-09-11   (select on this only)
  TEST  = 2024-09-11 .. 2026-09-11   (report on this; == the M1 dataset PR #9 used)

For every (pair, timeframe, family, threshold, stop, target) it reports TRAIN
net expectancy, then re-scores the TRAIN-selected leaders on TEST.

  python3 validation/speed_lab/sweep2.py
"""
from __future__ import annotations

import sys, time, json, itertools
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E

TRAIN_END = 1726012800000        # 2024-09-11T00:00:00Z  (start of the M1 files)
HOLD_HOURS = 96

TFS = [5, 15, 30, 60]
FAMS = ["rev", "mom", "don_fade", "don_break"]
KS = [2.0, 2.5, 3.0, 3.5]
SAS = [2.0, 3.0, 4.0, 6.0, 8.0]
TRS = [1.5, 2.0, 3.0, 4.0]


def eval_split(sym, tf, fam, k, sa, tr):
    d = E.load_ohlc(sym, tf, "m5")
    hold = max(8, int(HOLD_HOURS * 60 / tf))
    kw = (dict(k=k, stop_atr=sa, target_r=tr, n_ch=20) if fam in ("rev", "mom")
          else dict(n_ch=max(6, 240 // tf), stop_atr=sa, target_r=tr))
    s = E.signals(d, sym, fam, **kw)
    if s is None or len(s["idx"]) < 40:
        return None
    r = E.resolve(s, d, max_hold_bars=hold)
    ts = r["ts"]
    m_tr = ts < TRAIN_END
    m_te = ts >= TRAIN_END
    out = dict(sym=sym, tf=tf, fam=fam, k=k, sa=sa, tr=tr)
    for tag, m in (("tr", m_tr), ("te", m_te)):
        if m.sum() < 25:
            out.update({f"n_{tag}": int(m.sum()), f"eg_{tag}": 0.0, f"en_{tag}": 0.0,
                        f"pf_{tag}": 0.0, f"stop_{tag}": 0.0, f"cost_{tag}": 0.0,
                        f"wr_{tag}": 0.0})
            continue
        sub = {kk: vv[m] for kk, vv in r.items()}
        e = E.expectancy(s, sub, sym)
        out.update({f"n_{tag}": e["n"], f"eg_{tag}": e["e_gross"], f"en_{tag}": e["e_net"],
                    f"pf_{tag}": e["pf"], f"stop_{tag}": e["med_stop"],
                    f"cost_{tag}": e["cost_R"], f"wr_{tag}": e["wr"]})
    return out


def main():
    t0 = time.time()
    rows = []
    for sym in E.ALL_PAIRS:
        for tf, fam, k, sa, tr in itertools.product(TFS, FAMS, KS, SAS, TRS):
            if fam not in ("rev", "mom") and k != KS[0]:
                continue
            r = eval_split(sym, tf, fam, k, sa, tr)
            if r:
                rows.append(r)
        print(f"  {sym} done, {len(rows)} rows, {time.time()-t0:.0f}s", flush=True)

    Path("/tmp/speedlab_cache").mkdir(exist_ok=True)
    Path("/tmp/speedlab_cache/sweep2.json").write_text(json.dumps(rows))

    good_tr = [r for r in rows if r["n_tr"] >= 100 and r["en_tr"] > 0]
    good_tr.sort(key=lambda r: -r["en_tr"])

    print(f"\n{'='*118}")
    print(f"SCANNED {len(rows)} (pair, tf, family, params) COMBINATIONS ON 11 PAIRS x 4 YEARS")
    print(f"{'='*118}")
    print(f"TRAIN-positive (E_net>0, n>=100): {len(good_tr)} / {len(rows)}")
    surv = [r for r in good_tr if r["n_te"] >= 60 and r["en_te"] > 0]
    print(f"  ...of those, ALSO positive on the untouched TEST half: {len(surv)} "
          f"({len(surv)/max(len(good_tr),1)*100:.1f}%)")
    print(f"  -> TRAIN-only selection overstates viability by "
          f"{len(good_tr)/max(len(surv),1):.1f}x")

    print(f"\n{'='*118}")
    print("TOP 30 TRAIN-SELECTED CONFIGS, RE-SCORED ON THE HELD-OUT TEST HALF")
    print(f"{'='*118}")
    print(f"{'sym':<8}{'tf':>4}{'fam':<10}{'k':>5}{'SA':>5}{'TR':>5} | "
          f"{'nTR':>6}{'stopTR':>8}{'EnetTR':>9} | {'nTE':>6}{'stopTE':>8}{'costTE':>8}"
          f"{'EgrossTE':>10}{'EnetTE':>9}{'PF':>6}{'surv':>6}")
    print("-" * 118)
    for r in good_tr[:30]:
        ok = "YES" if (r["n_te"] >= 60 and r["en_te"] > 0) else "no"
        print(f"{r['sym']:<8}{r['tf']:>4}{r['fam']:<10}{r['k']:>5.1f}{r['sa']:>5.1f}"
              f"{r['tr']:>5.1f} | {r['n_tr']:>6}{r['stop_tr']:>8.2f}{r['en_tr']:>+9.4f} | "
              f"{r['n_te']:>6}{r['stop_te']:>8.2f}{r['cost_te']*100:>7.1f}%"
              f"{r['eg_te']:>+10.4f}{r['en_te']:>+9.4f}{r['pf_te']:>6.2f}{ok:>6}")

    print(f"\n{'='*118}")
    print("OUT-OF-SAMPLE SURVIVORS  (TRAIN E_net>0 AND TEST E_net>0)  — the only honest candidates")
    print(f"{'='*118}")
    surv.sort(key=lambda r: -r["en_te"])
    print(f"{'sym':<8}{'tf':>4}{'fam':<10}{'k':>5}{'SA':>5}{'TR':>5}{'nTE':>7}{'stopTE':>8}"
          f"{'cost%':>7}{'WR%':>7}{'Egross':>9}{'Enet':>9}{'PF':>6}{'trades/day':>12}")
    print("-" * 118)
    for r in surv[:30]:
        tpd = r["n_te"] / 730.0
        print(f"{r['sym']:<8}{r['tf']:>4}{r['fam']:<10}{r['k']:>5.1f}{r['sa']:>5.1f}"
              f"{r['tr']:>5.1f}{r['n_te']:>7}{r['stop_te']:>8.2f}{r['cost_te']*100:>6.1f}%"
              f"{r['wr_te']*100:>6.1f}%{r['eg_te']:>+9.4f}{r['en_te']:>+9.4f}"
              f"{r['pf_te']:>6.2f}{tpd:>12.2f}")

    Path("/tmp/speedlab_cache/survivors.json").write_text(json.dumps(surv[:60]))
    print(f"\nwrote /tmp/speedlab_cache/sweep2.json ({len(rows)} rows) and survivors.json")
    print(f"total {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
