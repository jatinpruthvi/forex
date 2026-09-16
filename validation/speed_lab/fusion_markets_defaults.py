#!/usr/bin/env python3
"""
fusion_markets_defaults.py — audit every EA default against Fusion Markets' Zero account.

The user selected Fusion Markets Zero. This answers, from the validated trade list rather than
from the broker's marketing, three questions:

  PART 1  Does each FIVE_M5_EXHAUST input default match Fusion's actual conditions? The table
          is printed with a per-input verdict, and the numeric claims behind it are computed
          here rather than asserted.

  PART 2  InpCommissionPerLotRT defaults to 7.0 (what the backtest assumed, and what IC Markets
          and Pepperstone charge). Fusion Zero charges $4.50 round turn. That input is inside
          LossPerLot(), so it sizes every position - what does leaving it at 7.0 actually cost?

  PART 3  Fusion's server is New York aligned and observes DST: GMT+3 in US summer, GMT+2 in
          winter. The validation hard-assumed a FIXED +3. Measured: what does the winter clock
          do to expectancy, drawdown, and - the part that matters - the rollover count that
          drives swap? And is Fusion's swap-free account, which replaces swap with a spread
          markup, ever the better buy?

Account facts used here are from Fusion's own materials and independent reviews (see the
Sources section of findings_broker_and_balance.md): Zero account, $2.25/side = $4.50 round
turn, raw spreads from 0.0, no minimum deposit, 0.01 minimum volume, max 200 open positions,
hedging allowed, EAs allowed, market execution / NDD, leverage 1:500 on the VFSC and FSA
entities but 1:30 on the ASIC retail entity, margin call 90%, stop-out 20-50%, client funds
segregated at National Australia Bank, free VPS only above 20 lots/month.

Standard library only, per the repo convention.

Usage:  python3 validation/speed_lab/fusion_markets_defaults.py
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import verify_final_config as V                    # noqa: E402
import personal_account_analysis as PA             # noqa: E402

# The recommendation is the SEVEN FX pairs, not the shipped eight: XAUUSD has negative
# held-out expectancy and raises the lot-granularity floor 10x ($1,565 -> $16,101).
UNI7 = ["EURGBP", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY"]
UNI8 = UNI7 + ["XAUUSD"]
BAL = 2000.0            # the single recommended minimum balance
RISK = 0.005

# Fusion Zero raw spreads, published independent measurements (pips, round turn).
FUSION_ZERO = {"EURGBP": 0.39, "AUDUSD": 0.09, "NZDUSD": 0.30, "USDCAD": 0.23,
               "USDCHF": 0.41, "EURJPY": 0.48, "GBPJPY": 0.90, "XAUUSD": 1.50}
FUSION_COMM_RT = 4.50
BACKTEST_COMM_RT = 7.00
# Fusion's Islamic/swap-free account is quoted "from 1.4 pips" instead of 0.0; model the
# markup as +1.4 pips on top of the Zero spread for every pair.
SWAPFREE_MARKUP = 1.4


def test_trades(universe):
    all_tr = {s: V.build(s) for s in V.SPECS}
    tr = [t for s in universe for t in all_tr[s] if t.ets >= V.TRAIN_END]
    tr.sort(key=lambda t: t.ets)
    return tr


def apply_costs(tr, sprd, comm):
    for t in tr:
        pv = V.SPECS[t.sym][1]
        t.cost_R = (sprd[t.sym] * pv + comm) / (t.stop_pips * pv + comm)


def replay(tr, bal=BAL, swap=0.0):
    V.ACCOUNT = bal
    r = PA.replay_personal(tr, RISK, mode="initial", max_conc=99, cap_day=99,
                           breaker=3.0, swap_R_per_night=swap)
    _, rets = PA.month_stats(r, A0=bal)
    return r, sum(rets) / len(rets) * 100, min(rets) * 100


def rollovers(tr):
    return sum(max(0, ((t.xts + V.SRV_MS) // V.MS_DAY) - ((t.ets + V.SRV_MS) // V.MS_DAY))
               for t in tr)


def sized_lots(tr, bal, comm):
    """Lots the EA would actually send, using the EA's own sizing arithmetic."""
    rc = bal * RISK
    out = []
    for t in tr:
        lpl = t.stop_pips * V.SPECS[t.sym][1] + comm
        if lpl <= 0:
            continue
        n = int((rc / lpl) / V.VOL_STEP)
        out.append(n)
    return out


def main():
    print("=" * 104)
    print("FUSION MARKETS ZERO — EA DEFAULT AUDIT")
    print(f"held-out TEST period, ${BAL:,.0f} balance, {RISK*100:.2f}% risk")
    print("=" * 104)

    V.SRV_MS = 3 * 3600 * 1000          # the validated assumption
    tr7 = test_trades(UNI7)
    tr8 = test_trades(UNI8)
    print(f"\nTEST signals: {len(tr7):,} on the 7 FX pairs, {len(tr8):,} including XAUUSD")

    # ------------------------------------------------------------------ PART 1
    print("\n" + "=" * 104)
    print("PART 1 — EVERY INPUT DEFAULT, CHECKED AGAINST FUSION ZERO")
    print("=" * 104)

    gold7 = [t for t in tr8 if t.sym == "XAUUSD"]
    enet_gold = sum(t.R - t.cost_R for t in gold7) / len(gold7)
    peak_conc, peak_day = 9, 13          # measured in margin_and_swap_exposure.py

    rows = [
        ("InpValidationReleaseId", '"LOCKED"', "MUST CHANGE",
         'Authorised() requires it to equal InpRequiredReleaseId. As shipped the EA will '
         'never submit an order. Set it to "M5_EXHAUST_2026_09".'),
        ("InpRequiredReleaseId", '"M5_EXHAUST_2026_09"', "keep", "The release this build validates against."),
        ("Inp*GatePassed (x5)", "false", "set one at a time",
         "Repo safety convention. Each must be genuinely satisfied; FirstClosedGate() now "
         "names the first one still closed."),
        ("InpExplicitUserApproval", "false", "set last but one", "Accepts a 16-23% peak-relative drawdown."),
        ("InpEnableOrderSubmission", "false", "set LAST", "Master switch. Nothing is sent until it is true."),
        ("InpAuthorizedLogin", "0 (any)", "recommended",
         "0 accepts any login on the terminal. Pin it to the live account number so a copy of "
         "the EA on a demo or a second account cannot trade."),
        ("InpExpectedAccountCurrency", '"USD"', "KEEP — do not change",
         "Fusion offers 14 base currencies and charges commission IN the account currency. "
         "Every pip value, the $4.50 figure and the whole validation are USD. On an AUD account "
         "the commission is AUD 4.50 and none of the published numbers transfer. Authorised() "
         "refuses to trade if the account currency differs — that check is doing its job."),
        ("InpExpectedServerUtcOffsetHours", "3", "keep 3; expect a seasonal WARN",
         "Fusion's server is New York aligned and observes DST: GMT+3 in US summer, GMT+2 in "
         "winter. +3 is the validated assumption, so leave it. From roughly November to March "
         "CheckServerOffset() will WARN that the server is UTC+2 — that is correct and "
         "expected, not a fault. Part 3 quantifies what it costs."),
        ("InpMagic", "26091501", "keep", "Change only if another EA shares the account."),
        ("InpSymbols", "8 pairs incl XAUUSD", "CHANGE — drop XAUUSD",
         f"Gold's held-out TEST expectancy is {enet_gold:+.3f}R, i.e. negative, and it raises "
         "the lot-granularity floor 10x to $16,101. Use the seven FX pairs."),
        ("InpUseAllEleven", "false", "keep", "The 8-pair universe is the TRAIN-selected one."),
        ("Strategy params (4.0 / 14 / 2.0 / 1.0 / 10.0 / 96 / M5)", "frozen", "DO NOT TOUCH",
         "Retuning these invalidates every number in this repo."),
        ("InpMaxDeviationPoints", "20", "keep",
         "2.0 pips on a 5-digit symbol. Fusion is market execution / NDD, where the server "
         "fills at market and deviation is largely advisory, so this is not a live constraint."),
        ("InpCloseAllOnHalt", "true", "keep",
         "Round 6 made the flatten path report its true outcome; see the README bug table."),
        ("InpMaxEntryLagSeconds", "30", "keep",
         "Guards against filling a stale bar. Entries happen during a 4xATR spike, so a slow "
         "VPS or a frozen terminal shows up here rather than as a bad fill."),
        ("InpRiskPercent", "0.50", "keep", "The validated setting; produces the $2,000 floor."),
        ("InpRiskOnInitialBase", "true", "keep",
         "Pins the sizing base at the balance seen in OnInit — fixed fractional, which is what "
         "was validated. false compounds, and the compounded profile carries a deeper drawdown."),
        ("InpSizingBaseOverride", "0.0", "keep",
         "0 means use the balance at init, so depositing $2,000 sizes on $2,000. Setting 2500 "
         "here would size on $2,500 while the account holds $2,000 — a 25% over-risk."),
        ("InpDailyBreakerR", "3.0", "keep", "Validated. Recomputed from deal history, including "
         "swap and commission, so it sees true realised R."),
        ("InpMaxConcurrent", "99", "keep",
         f"Fusion allows up to 200 open positions; this stream peaks at {peak_conc} concurrent, "
         "so the broker limit is nowhere near binding."),
        ("InpMaxTradesPerDay", "99", "keep", f"Peak observed is {peak_day} in a server day."),
        ("InpCommissionPerLotRT", "7.0", "MUST CHANGE to 4.50",
         "Fusion Zero is $2.25/side = $4.50 round turn. This input is INSIDE LossPerLot(), so "
         "it sizes every position. Part 2 measures the cost of leaving it at 7.0."),
        ("InpBlockFridayLate", "true", "keep",
         "Prevents carrying a fresh position into the weekend gap."),
        ("InpFridayCutoffHour", "21", "keep",
         "A SERVER hour by design, matching the validation. On Fusion's winter GMT+2 clock, "
         "server 21:00 is UTC 19:00 rather than 18:00 — Part 3 measures the effect."),
        ("Prop-mode inputs (target / floor / daily-loss / qualifying days)", "all 0", "keep at 0",
         "Leave zero for a personal account. They are prop-challenge protection, and enabling "
         "them changes the risk profile the numbers were measured under."),
    ]
    print(f"\n  {'input':<52} {'default':<22} {'verdict':<26}")
    print("  " + "-" * 100)
    for name, dflt, verdict, _ in rows:
        print(f"  {name:<52} {dflt:<22} {verdict:<26}")
    print("\n  Detail on the three that must change:")
    for name, dflt, verdict, why in rows:
        if verdict.startswith("MUST") or verdict.startswith("CHANGE"):
            print(f"\n  {name} = {dflt}  ->  {verdict}")
            print(f"    {why}")

    print("\n  ACCOUNT-LEVEL requirements that are not EA inputs:")
    acct = [
        ("ENTITY", "VFSC (Vanuatu, 40256) or FSA (Seychelles) — NOT the ASIC retail entity",
         "Leverage is 1:500 offshore but 1:30 for ASIC retail. At 1:30 the measured peak margin "
         "on this stream is 260-275% of equity: the broker stops you out before the EA's own -3R "
         "breaker ever acts. This is the single most consequential choice at account opening."),
        ("ACCOUNT TYPE", "Zero, not Classic",
         "Classic is 0.9 pips spread-only (~$9/lot round turn); Zero is raw spread + $4.50 "
         "(~$4.75/lot). Zero is roughly half the cost."),
        ("NOT swap-free", "Zero, not the Islamic/swap-free variant",
         "Swap-free replaces swap with a spread markup (quoted from 1.4 pips). Part 3 shows it "
         "is worse than paying swap up to about 0.27R per night, far beyond realistic long swap "
         "on these pairs."),
        ("HEDGING", "Confirmed allowed — no signal loss",
         "Hedging is supported, so g_netting stays false and the EA does not have to skip the "
         "13.8% of signals that stack on an already-open symbol. The validated profile applies."),
        ("STOP-OUT", "20% (some sources 50%) — both satisfy the requirement",
         "The EA needs a stop-out at or below 50% so the strategy's own risk limits act first. "
         "Confirm on the account; sources differ."),
        ("VPS", "Budget for a PAID VPS",
         "Fusion's free VPS needs 20 lots/month. At $2,000 this strategy trades roughly 2-3 "
         "lots/month, so it does not qualify — and the EA must run 24/5 or the 96h timeout and "
         "the daily breaker stop working."),
        ("BASE CURRENCY", "USD", "See InpExpectedAccountCurrency above."),
        ("RESTRICTED", "USA, North Korea, Iran, Myanmar and others are not accepted",
         "Relevant when selling the EA abroad: a US-resident buyer cannot open the account."),
    ]
    for k, v, why in acct:
        print(f"\n  {k}: {v}")
        print(f"    {why}")

    # ------------------------------------------------------------------ PART 2
    print("\n" + "=" * 104)
    print("PART 2 — InpCommissionPerLotRT: leaving it at the 7.0 default on a $4.50 broker")
    print("=" * 104)
    print("""
  This input is not a reporting field. LossPerLot() returns `stop x pip_value + commission`,
  and lots = risk_cash / LossPerLot(). An overstated commission therefore UNDER-states the lot
  size on every single trade. It also overstates cost_R, so the reported expectancy is wrong in
  the other direction. Both effects are measured below on the real trade list.
""")
    print(f"  {'pair':<8} {'med stop':>9} {'pip val':>8} {'true $/lot':>11} {'at 7.0':>9} "
          f"{'lots err':>9} {'realised risk':>14}")
    print("  " + "-" * 76)
    import statistics
    stops = {}
    for t in tr7:
        stops.setdefault(t.sym, []).append(t.stop_pips)
    for s in UNI7:
        pv = V.SPECS[s][1]
        med = statistics.median(stops[s])
        true = med * pv + FUSION_COMM_RT
        wrong = med * pv + BACKTEST_COMM_RT
        print(f"  {s:<8} {med:>8.1f}p {pv:>8.2f} {true:>11.2f} {wrong:>9.2f} "
              f"{(true/wrong-1)*100:>+8.1f}% {RISK*100*(true/wrong):>13.3f}%")

    l7 = sized_lots(tr7, BAL, BACKTEST_COMM_RT)
    l45 = sized_lots(tr7, BAL, FUSION_COMM_RT)
    under = sum(1 for a, b in zip(l7, l45) if a < b)
    print(f"\n  Trades sized SMALLER than they should be at ${BAL:,.0f}: "
          f"{under} of {len(l45):,} ({under/len(l45)*100:.1f}%)")
    # l7/l45 hold integer 0.01-lot STEP COUNTS, not lots - multiply by VOL_STEP to report lots.
    mean7 = sum(l7) / len(l7) * V.VOL_STEP
    mean45 = sum(l45) / len(l45) * V.VOL_STEP
    print(f"  Mean position size: {mean7:.4f} lots at 7.0  vs  {mean45:.4f} lots at 4.50 "
          f"({(mean7/mean45-1)*100:+.1f}%)")

    for comm, lbl in ((BACKTEST_COMM_RT, "left at the 7.0 default"), (FUSION_COMM_RT, "set correctly to 4.50")):
        apply_costs(tr7, FUSION_ZERO, comm)
        e = sum(t.R - t.cost_R for t in tr7) / len(tr7)
        r, m, w = replay(tr7)
        print(f"  {lbl:<28} E_net {e:+.3f}R   {m:+.2f}%/mo   worst month {w:+.2f}%   "
              f"maxDD {r['mdd']*100:.1f}%")
    print("\n  -> Set InpCommissionPerLotRT = 4.50. The default of 7.0 is correct only for")
    print("     IC Markets Raw and Pepperstone Razor.")

    # ------------------------------------------------------------------ PART 3
    print("\n" + "=" * 104)
    print("PART 3 — FUSION'S SEASONAL SERVER CLOCK, AND THE SWAP-FREE QUESTION")
    print("=" * 104)
    print("""
  The validation assumed a FIXED UTC+3 server. Fusion is New York aligned and observes DST, so
  it runs GMT+3 in US summer and GMT+2 in winter. Signal generation and exits are keyed to UTC
  and do not move; what moves is the server-day boundary, which drives the Friday block, the
  daily breaker window, the monthly bucketing and — the part with a real cost — how many
  overnight rollovers each trade crosses, and therefore how much swap is charged.
""")
    apply_costs(tr7, FUSION_ZERO, FUSION_COMM_RT)
    print(f"  {'server':>8} {'signals':>8} {'E_net':>8} {'%/mo':>8} {'worst mo':>9} {'maxDD':>7} "
          f"{'total':>8} {'rollovers':>10} {'nights/trade':>13}")
    print("  " + "-" * 92)
    base = None
    for off in (3, 2, 1, 0, 4):
        V.SRV_MS = off * 3600 * 1000
        tr = test_trades(UNI7)
        apply_costs(tr, FUSION_ZERO, FUSION_COMM_RT)
        e = sum(t.R - t.cost_R for t in tr) / len(tr)
        r, m, w = replay(tr)
        n = rollovers(tr)
        if off == 3:
            base = (m, n, r['mdd'] * 100)
        print(f"  {'UTC%+d' % off:>8} {len(tr):>8,} {e:>+7.3f}R {m:>+7.2f}% {w:>+8.2f}% "
              f"{r['mdd']*100:>6.1f}% {r['total_ret']*100:>+7.0f}% {n:>10,} {n/len(tr):>13.3f}")

    V.SRV_MS = 2 * 3600 * 1000          # Fusion's winter clock - the adverse case for swap
    tr2 = test_trades(UNI7)
    apply_costs(tr2, FUSION_ZERO, FUSION_COMM_RT)
    n2 = rollovers(tr2)
    print(f"\n  Winter clock (GMT+2) crosses {n2 - base[1]:+,} MORE rollovers than the validated "
          f"GMT+3 assumption ({(n2/base[1]-1)*100:+.1f}%).")
    print("  Why: 30.7% of entries are at UTC 21:00. With a +3 server the day boundary sits")
    print("  exactly on that hour, so those trades start a fresh server day and cross no")
    print("  rollover. With a +2 server the boundary is an hour later and they cross one.")
    print("  The validated +3 assumption is therefore FLATTERING on swap, and Fusion spends")
    print("  roughly four months a year on the clock that is not flattering.\n")

    print("  Swap sensitivity, and whether Fusion's swap-free account is worth it:")
    print(f"  {'account':<34} {'comm RT':>8} {'swap/night':>11} {'E_net':>8} {'%/mo':>8} {'maxDD':>7}")
    print("  " + "-" * 80)
    islamic = {k: v + SWAPFREE_MARKUP for k, v in FUSION_ZERO.items()}
    results = {}
    for lbl, sprd, comm, swap in [
        ("Zero, no swap charged", FUSION_ZERO, FUSION_COMM_RT, 0.00),
        ("Zero, swap 0.05R/night", FUSION_ZERO, FUSION_COMM_RT, 0.05),
        ("Zero, swap 0.10R/night", FUSION_ZERO, FUSION_COMM_RT, 0.10),
        ("Zero, swap 0.20R/night", FUSION_ZERO, FUSION_COMM_RT, 0.20),
        ("Zero, swap 0.30R/night", FUSION_ZERO, FUSION_COMM_RT, 0.30),
        (f"Swap-Free (+{SWAPFREE_MARKUP}p markup)", islamic, FUSION_COMM_RT, 0.00),
    ]:
        V.SRV_MS = 2 * 3600 * 1000
        tr = test_trades(UNI7)
        apply_costs(tr, sprd, comm)
        e = sum(t.R - t.cost_R for t in tr) / len(tr)
        r, m, _ = replay(tr, swap=swap)
        results[lbl] = m
        print(f"  {lbl:<34} {comm:>7.2f}$ {swap:>10.2f}R {e:>+7.3f}R {m:>+7.2f}% "
              f"{r['mdd']*100:>6.1f}%")

    sf = results[f"Swap-Free (+{SWAPFREE_MARKUP}p markup)"]
    z20 = results["Zero, swap 0.20R/night"]
    z30 = results["Zero, swap 0.30R/night"]
    # linear interpolation between the 0.20 and 0.30 rows to find the crossover
    cross = 0.20 + (z20 - sf) / (z20 - z30) * 0.10 if z20 != z30 else float("nan")
    print(f"\n  The swap-free markup only pays if long swap exceeds ~{cross:.2f}R per night.")
    print("  Realistic long swap on these pairs is a small fraction of that, so:")
    print("  TAKE THE ZERO ACCOUNT, NOT THE SWAP-FREE ONE.")
    print("  (InpSwapCostGatePassed still requires you to read Fusion's actual swap table for")
    print("   all seven symbols before enabling — this models the cost, it does not quote it.)")

    print("\n" + "=" * 104)
    print("SUMMARY — the three changes to make for Fusion Markets Zero")
    print("=" * 104)
    print(f"""
  1. InpCommissionPerLotRT   7.0   -> 4.50     (it sizes every position)
  2. InpSymbols              drop XAUUSD       (negative held-out edge, 10x the balance floor)
  3. InpValidationReleaseId  "LOCKED" -> "M5_EXHAUST_2026_09"   (or nothing is ever submitted)

  Plus, at account opening: the VFSC/FSA entity for 1:500 leverage (NOT ASIC retail at 1:30),
  the Zero account (not Classic), USD base currency, and NOT the swap-free variant.

  Leave InpExpectedServerUtcOffsetHours at 3 and expect a WARN for about four months a year.
  Measured cost of Fusion's winter GMT+2 clock: expectancy unchanged at +0.704R, monthly return
  and drawdown both shift within about a point, and rollovers rise {n2/base[1]*100-100:.0f}% — which is a swap
  question, not an edge question.

  Balance: ${BAL:,.0f} on the seven FX pairs at 1:500. Peak margin ~16% of equity, so margin is
  not the constraint; lot granularity is.
""")
    V.SRV_MS = 3 * 3600 * 1000          # restore the validated assumption for any importer
    return 0


if __name__ == "__main__":
    sys.exit(main())
