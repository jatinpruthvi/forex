#!/usr/bin/env python3
"""
broker_cost_and_balance.py — what a broker must offer, and how little you can start with.

Two questions, both answered from the VALIDATED trade list rather than from marketing pages:

  PART 1 - SPREAD BUDGET. The frozen backtest charges round-turn spread = 0.55 x the
    standard spread (a raw/ECN account) plus $7/lot commission, inside every trade. That is
    the only cost assumption the published expectancy was ever measured under. So:
      * what each pair costs, as a fraction of 1R, at that assumption;
      * the BREAK-EVEN spread per pair - the widest quote at which the pair still has
        positive expectancy. This is the number to check a broker against;
      * whether a raw account (tight spread + commission) actually beats a standard account
        (no commission + wide spread) for THIS strategy. Wide stops change the answer,
        because 1R is large, so a flat commission is a smaller slice of it.

  PART 2 - MINIMUM BALANCE. Three separate floors, and the binding one is not the obvious:
      * lot granularity: lots = floor(risk / loss_per_lot / 0.01) x 0.01, and the EA skips
        the trade below 0.01 lots. That sets a hard balance floor per trade;
      * margin: with only 2 positions allowed at once, how much leverage a given balance
        needs to avoid being margin-constrained;
      * degradation: a full replay at each balance, showing skipped trades, monthly return
        and drawdown, so the trade-off is visible rather than asserted.

Everything is standard-library only, per the repo convention.

Usage:  python3 validation/speed_lab/broker_cost_and_balance.py
"""
from __future__ import annotations

import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import verify_final_config as V                    # noqa: E402
import personal_account_analysis as PA             # noqa: E402
import margin_and_swap_exposure as MS              # noqa: E402

# TRAIN-selected 8-pair universe - the EA's default, and the one every quoted number uses.
UNIVERSE = ["EURGBP", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY", "XAUUSD"]
RISK = 0.005                       # 0.50% - the validated setting
# These MUST match the EA's shipped inputs, not replay_personal()'s defaults. The EA sets
# InpMaxConcurrent = 99 and InpMaxTradesPerDay = 99 ("take every signal", the validated best
# for a personal account); replay_personal defaults to 2 and 5, which are the PROP-FIRM caps.
# Using the prop caps here silently halves the reported return (+6.80%/mo instead of
# +12.74%/mo) - the caps are firm protection, not edge protection.
EA_CONC, EA_DAY, EA_BREAKER = 99, 99, 3.0
CONTRACT_FX, CONTRACT_XAU = 100_000.0, 100.0


def bisect_breakeven(trades, pv, comm):
    """Widest round-turn spread, in pips, at which mean(R - cost_R) is still >= 0."""
    def enet(s_pips):
        tot = 0.0
        for t in trades:
            denom = t.stop_pips * pv + comm
            tot += t.R - (s_pips * pv + comm) / denom
        return tot / len(trades)

    lo, hi = 0.0, 200.0
    if enet(hi) > 0:
        return hi
    for _ in range(60):
        mid = (lo + hi) / 2
        if enet(mid) > 0:
            lo = mid
        else:
            hi = mid
    return lo


def main():
    print("=" * 108)
    print("BROKER COST BUDGET & MINIMUM BALANCE - frozen config, held-out TEST period")
    print("=" * 108)

    # Build the trade list ONCE. cost_R is recomputed analytically below rather than by
    # rebuilding, because it is a closed-form function of the spread: that makes the whole
    # sweep exact and near-instant.
    all_trades = {s: V.build(s) for s in V.SPECS}
    test = {s: [t for t in all_trades[s] if t.ets >= V.TRAIN_END] for s in V.SPECS}
    uni = [t for s in UNIVERSE for t in test[s]]
    uni.sort(key=lambda t: t.ets)
    print(f"\nTEST trades, {len(UNIVERSE)}-pair universe: {len(uni):,}")

    print("\n" + "=" * 108)
    print("PART 0 - JURISDICTION: READ THIS BEFORE ANY OF THE NUMBERS BELOW MATTER")
    print("=" * 108)
    print("""
  This analysis was prepared for a user resident in India. Under FEMA 1999 a person resident
  in India may deal in foreign exchange only through an RBI-authorised person, and may trade
  currency derivatives only on a recognised Indian exchange (NSE / BSE / MSE) through a
  SEBI-registered broker. OTC spot forex and CFDs on non-INR pairs through an offshore broker
  are not permitted, and the Liberalised Remittance Scheme expressly prohibits remitting
  funds abroad for margin trading or forex speculation.

  Every instrument in this strategy's universe is affected. The 8 pairs are EURGBP, AUDUSD,
  NZDUSD, USDCAD, USDCHF, EURJPY, GBPJPY and XAUUSD - none of them is an INR pair, and none
  is among the exchange-traded contracts available in India (USDINR, EURINR, GBPINR, JPYINR
  futures/options, plus EURUSD, GBPUSD and USDJPY cross-currency futures). The strategy also
  needs continuous 24x5 M5 spot bars including the daily rollover, which exchange-traded
  currency futures do not provide.

  The RBI Alert List (95 entities, updated 19 November 2025) names, among others: IC Markets,
  Pepperstone, Fusion Markets, Tickmill, FP Markets, Exness, XM, IG Markets, Admiral, Think
  Markets, BlackBull, Vantage, VT Markets, HF Markets/HotForex - i.e. every broker modelled
  in Part 3 below - and also lists MetaTrader 4 and MetaTrader 5 themselves, plus the prop
  firms FTMO, FundedNext and Smart Prop Trader. RBI states the list is NOT exhaustive, so
  absence from it is not authorisation.

  Reported penalties under FEMA s.13: up to three times the amount involved or Rs 2 lakh
  (whichever is higher), Rs 5,000 per day for a continuing violation, and up to 5 years
  imprisonment for a serious or wilful violation under s.13(1C); funds in unauthorised
  offshore accounts may be attached.

  Consequence for this report: the broker comparison in Part 3 is provided as cost analysis,
  because the spread budget and the rollover finding are real properties of the strategy and
  are needed to interpret any backtest. It is NOT a recommendation to open an account, and it
  should not be acted on by a person resident in India. Confirm your own residency status and
  get advice from a professional qualified in Indian exchange-control law before doing
  anything with real money. If your residency is not Indian, Parts 1-4 apply as written.
""")

    # --------------------------------------------------------------- PART 1
    print("\n" + "=" * 108)
    print("PART 1 - SPREAD BUDGET: what a broker must offer")
    print("=" * 108)
    print(f"\nThe validated cost model charges 0.55 x standard spread (raw/ECN account) + "
          f"$7.00/lot round turn.")
    print("Costs below are as a FRACTION OF 1R - the slice of every trade's risk that the")
    print("broker keeps. 'Break-even spread' is the widest quote with positive expectancy.\n")

    print(f"  {'pair':<8} {'std sprd':>9} {'raw sprd':>9} {'med stop':>9} {'cost/1R':>8} "
          f"{'E_gross':>8} {'E_net':>7} {'break-evn':>10} {'headroom':>9}  {'n':>5}")
    print(f"  {'':<8} {'(pips)':>9} {'(pips)':>9} {'(pips)':>9} {'(%)':>8} {'(R)':>8} "
          f"{'(R)':>7} {'(pips)':>10} {'(x)':>9}")
    print("  " + "-" * 104)

    rows = []
    for s in UNIVERSE:
        ts = test[s]
        if not ts:
            continue
        pip, pv, sprd = V.SPECS[s]
        raw_pips = sprd * V.RAW_SCALE / pip
        std_pips = sprd / pip
        stops = sorted(t.stop_pips for t in ts)
        med_stop = stops[len(stops) // 2]
        eg = sum(t.R for t in ts) / len(ts)
        en = sum(t.R - t.cost_R for t in ts) / len(ts)
        cost = sum(t.cost_R for t in ts) / len(ts)
        be = bisect_breakeven(ts, pv, V.COMM_RT)
        # A pair whose GROSS edge is already negative loses at any spread, including zero.
        # Printing "0.00 pips" would read as "needs a tighter broker" when the real problem
        # is that it has no edge on this period at all.
        dead = eg <= 0
        rows.append((s, std_pips, raw_pips, med_stop, cost, eg, en, be,
                     0.0 if dead else be / raw_pips, len(ts), dead))
        print(f"  {s:<8} {std_pips:>9.2f} {raw_pips:>9.2f} {med_stop:>9.1f} "
              f"{cost*100:>7.1f}% {eg:>+8.3f} {en:>+7.3f} "
              f"{'NEG EDGE' if dead else f'{be:>7.2f}p'} "
              f"{'n/a' if dead else f'{be/raw_pips:>6.1f}x'}  {len(ts):>5,}")

    tot_c = sum(t.cost_R for t in uni) / len(uni)
    tot_g = sum(t.R for t in uni) / len(uni)
    tot_n = tot_g - tot_c
    print("  " + "-" * 104)
    print(f"  {'ALL 8':<8} {'':>9} {'':>9} {'':>9} {tot_c*100:>7.1f}% {tot_g:>+8.3f} "
          f"{tot_n:>+7.3f}")
    print(f"\n  The broker keeps {tot_c*100:.1f}% of 1R on the validated quotes. Gross edge is "
          f"{tot_g:+.3f}R; net is {tot_n:+.3f}R.")
    print(f"  Costs consume {tot_c/tot_g*100:.0f}% of the gross edge - that is the whole margin "
          f"of safety, and it is why a wide-spread broker is not a rounding error here.")

    # headroom, ranked
    print("\n  Headroom before a pair turns unprofitable (break-even / validated raw spread):")
    for s, std, raw, med, cost, eg, en, be, hr, n, dead in sorted(rows, key=lambda r: r[8]):
        if dead:
            print(f"    {s:<8}   n/a  NEGATIVE GROSS EDGE on TEST - no spread makes it work")
            continue
        bar = "#" * max(1, int(hr * 6))
        flag = "  <-- tightest, broker choice matters most" if hr < 3.5 else ""
        print(f"    {s:<8} {hr:>5.1f}x  raw {raw:.2f} -> break-even {be:.2f} pips   {bar}{flag}")

    # -------- TRAIN vs TEST per pair --------
    # The universe was selected on TRAIN and every quoted number is TEST. Showing both stops
    # a pair that merely changed regime from being mistaken for one that never worked, and it
    # is the only honest way to present a pair that is negative on TEST.
    print("\n  Same pairs, TRAIN (selection period) vs TEST (held out). A pair negative on")
    print("  TEST but strongly positive on TRAIN changed regime; dropping it on TEST evidence")
    print("  alone would be fitting to the held-out data, which is how this repo's own PR #9")
    print("  overstated itself by 2.5x. So this is information, not a retune.\n")
    print(f"  {'pair':<8} {'TRAIN E_net':>12} {'TEST E_net':>11} {'TRAIN n':>8} {'TEST n':>7}  verdict")
    print("  " + "-" * 72)
    for s_ in UNIVERSE:
        tr = [t for t in all_trades[s_] if t.ets < V.TRAIN_END]
        te = test[s_]
        if not tr or not te:
            continue
        e_tr = sum(t.R - t.cost_R for t in tr) / len(tr)
        e_te = sum(t.R - t.cost_R for t in te) / len(te)
        v = ("held up" if e_te > 0.66 * e_tr else
             "DECAYED" if e_te > 0 else "NEGATIVE on TEST")
        print(f"  {s_:<8} {e_tr:>+11.3f}R {e_te:>+10.3f}R {len(tr):>8,} {len(te):>7,}  {v}")

    # -------- raw vs standard account --------
    print("\n  Raw/ECN vs standard account - which is actually cheaper for THIS strategy?")
    print("  A standard account charges no commission but quotes the full spread. Because the")
    print("  stops here are wide (median 2-3x ATR), 1R is large in dollars, so the flat $7")
    print("  commission is a SMALL slice of it - which favours the raw account.\n")
    print(f"  {'pair':<8} {'raw: 0.55x sprd + $7 RT':>26} {'standard: 1.0x sprd + $0':>26} "
          f"{'winner':>10} {'E_net gain':>12}")
    print("  " + "-" * 90)
    raw_wins = 0
    for s in UNIVERSE:
        ts = test[s]
        if not ts:
            continue
        pip, pv, sprd = V.SPECS[s]
        raw_pips, std_pips = sprd * V.RAW_SCALE / pip, sprd / pip

        def enet(sp, comm):
            return sum(t.R - (sp * pv + comm) / (t.stop_pips * pv + comm) for t in ts) / len(ts)

        e_raw, e_std = enet(raw_pips, V.COMM_RT), enet(std_pips, 0.0)
        win = "RAW" if e_raw > e_std else "STANDARD"
        raw_wins += e_raw > e_std
        print(f"  {s:<8} {e_raw:>+25.4f}R {e_std:>+25.4f}R {win:>10} "
              f"{abs(e_raw-e_std):>11.4f}R")
    print(f"\n  -> raw account wins on {raw_wins}/{len(UNIVERSE)} pairs. Choose a RAW/ECN account "
          f"type, not a standard one,")
    print("     even though it advertises a commission. The commission is cheaper than the spread.")

    # -------- spread multiplier sweep --------
    print("\n  Sensitivity: what happens to the strategy as your broker's spread widens?")
    print("  (multiplier applies to the raw spread on every pair; $7/lot commission unchanged)\n")
    print(f"  {'x validated':>11} {'E_net':>8} {'vs base':>9} {'mean %/mo':>10} {'median %/mo':>12} "
          f"{'worst mo':>9} {'maxDD':>7}")
    print("  " + "-" * 78)
    base_month = None
    for mult in (0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0):
        for t in uni:
            pip, pv, sprd = V.SPECS[t.sym]
            t.cost_R = ((sprd * V.RAW_SCALE * mult / pip) * pv + V.COMM_RT) / (t.stop_pips * pv + V.COMM_RT)
        en = sum(t.R - t.cost_R for t in uni) / len(uni)
        V.ACCOUNT = 2500.0
        res = PA.replay_personal(uni, RISK, mode="initial", max_conc=EA_CONC,
                                 cap_day=EA_DAY, breaker=EA_BREAKER)
        _, rets = PA.month_stats(res, A0=2500.0)
        mean, med = sum(rets) / len(rets) * 100, sorted(rets)[len(rets) // 2] * 100
        worst, mdd = min(rets) * 100, res["mdd"] * 100
        if mult == 1.0:
            base_month, base_en = mean, en
        print(f"  {mult:>10.2f}x {en:>+8.4f} {en/tot_n-1:>+8.0%} {mean:>+9.2f}% {med:>+11.2f}% "
              f"{worst:>+8.2f}% {mdd:>6.1f}%")
    # restore the validated cost_R on every trade: the sweep mutated objects that Part 2
    # also replays, so leaving it at 3.0x would silently poison the balance analysis.
    for t in uni:
        pip, pv, sprd = V.SPECS[t.sym]
        t.cost_R = ((sprd * V.RAW_SCALE / pip) * pv + V.COMM_RT) / (t.stop_pips * pv + V.COMM_RT)
    chk = sum(t.R - t.cost_R for t in uni) / len(uni)
    assert abs(chk - tot_n) < 1e-12, f"cost_R not restored: {chk} vs {tot_n}"

    print(f"\n  Break-even for the whole 8-pair universe is between the rows above; per-pair")
    print(f"  ceilings are in the headroom table. A broker quoting more than ~2x the validated")
    print(f"  raw spread on EURGBP/NZDUSD/GBPJPY/XAUUSD removes most of the edge.")

    # --------------------------------------------------------------- PART 2
    print("\n" + "=" * 108)
    print("PART 2 - MINIMUM INITIAL BALANCE")
    print("=" * 108)

    # --- floor 1: lot granularity ---
    print("\n  Floor 1 - LOT GRANULARITY (the binding one, and not the obvious one)")
    print("  The EA sizes lots = floor(risk / loss_per_lot / 0.01) x 0.01 and SKIPS the trade")
    print("  below 0.01 lots. risk = balance x 0.50%, so a trade is takeable only when")
    print("  balance >= 0.01 x loss_per_lot / 0.005 = 2 x loss_per_lot.\n")
    print(f"  {'pair':<8} {'med $/lot':>10} {'p95 $/lot':>10} {'max $/lot':>10} "
          f"{'min bal (med)':>14} {'min bal (worst)':>16}")
    print("  " + "-" * 76)
    global_max = 0.0
    global_p95 = 0.0
    for s in UNIVERSE:
        ts = test[s]
        if not ts:
            continue
        lpls = sorted(t.stop_pips * V.SPECS[s][1] + V.COMM_RT for t in ts)
        med, p95, mx = lpls[len(lpls)//2], lpls[int(len(lpls)*0.95)], lpls[-1]
        global_max = max(global_max, mx)
        global_p95 = max(global_p95, p95)
        print(f"  {s:<8} {med:>10,.0f} {p95:>10,.0f} {mx:>10,.0f} "
              f"{2*med:>13,.0f} {2*mx:>15,.0f}")
    print("  " + "-" * 76)
    # XAUUSD alone sets this floor, and it is an order of magnitude above every other pair
    # because a gold stop is ~93 pips and a 100oz contract makes each pip worth $10. Show
    # what the floor becomes without it, since that is the difference between a $1,600
    # account and a $16,000 one.
    fx_max = max(mx for s, std, raw, med, cost, eg, en, be, hr, n, dead in rows if s != "XAUUSD"
                 for mx in [max(t.stop_pips * V.SPECS[s][1] + V.COMM_RT for t in test[s])])
    print(f"  Excluding XAUUSD, the worst trade costs ${fx_max:,.0f}/lot -> floor ${2*fx_max:,.0f}.")
    print(f"  XAUUSD alone raises the floor {global_max/fx_max:.0f}x, from ${2*fx_max:,.0f} to "
          f"${2*global_max:,.0f}.")
    print(f"  Worst single trade across all 8 pairs costs ${global_max:,.0f} per lot to lose 1R.")
    print(f"    -> at 0.50% risk, a balance of ${2*global_max:,.0f} can take EVERY trade the")
    print(f"       strategy generates, including the widest-stop outliers.")
    print(f"    -> ${2*global_p95:,.0f} covers 95% of trades on every pair.")

    # --- floor 2: margin ---
    # Average TEST-period close per symbol. Notional is lots x contract x the USD price of
    # the BASE currency, never the quoted price: for GBPJPY the quote is JPY per GBP, so
    # using it directly overstates notional by ~200x. MS.BASE carries that mapping. EURUSD
    # and GBPUSD are not in the universe but are needed as USD references.
    px = {}
    for _s in V.SPECS:
        _ts, _o, _h, _l, _c = V.load(_s)
        _m = [x for x, t in zip(_c, _ts) if t >= V.TRAIN_END]
        px[_s] = sum(_m) / len(_m)

    print("\n  Floor 2 - MARGIN, measured on the ACTUAL trade stream")
    print("  Not a synthetic worst case: this replays every TEST trade under the EA's own")
    print("  gates and tracks real margin usage bar by bar. The 8-pair stream reaches")
    print("  9 concurrent positions and 13 trades in a day at its peak, so sizing margin")
    print("  for 2 positions would be badly wrong.\n")

    def margin_run(bal, lev):
        """Replay with the EA's gates; return peak margin as a fraction of equity."""
        rc = bal * RISK
        ev = []
        for t in uni:
            ev.append((t.ets, 0, t)); ev.append((t.xts, 1, t))
        ev.sort(key=lambda x: (x[0], x[1], x[2].sym))
        cur, peak = 0.0, 0.0
        open_m = {}
        day_key, day_net, locked = -1, 0.0, False
        for ts, kind, t in ev:
            dk = (ts + V.SRV_MS) // V.MS_DAY
            if dk != day_key:
                day_key, day_net, locked = dk, 0.0, False
            if kind == 1:
                if id(t) in open_m:
                    cur -= open_m.pop(id(t))
                continue
            if locked:
                continue
            lpl = t.stop_pips * V.SPECS[t.sym][1] + V.COMM_RT
            lots = int((rc / lpl) / V.VOL_STEP) * V.VOL_STEP
            if lots < V.VOL_MIN:
                continue
            if day_net <= -(EA_BREAKER * rc):
                locked = True
                continue
            day_net += -rc                        # assume the worst: every entry first loses
            _ccy, ref = MS.BASE[t.sym]
            usd_px = 1.0 if ref is None else px[ref]
            contract = CONTRACT_XAU if t.sym == "XAUUSD" else CONTRACT_FX
            m = lots * contract * usd_px / lev
            open_m[id(t)] = m
            cur += m
            peak = max(peak, cur)
        return peak / bal

    lev_tiers = (30, 50, 100, 200, 500)
    print(f"  {'balance':>9}" + "".join(f"{('1:'+str(L)):>11}" for L in lev_tiers))
    print("  " + "-" * (9 + 11 * len(lev_tiers)))
    for bal in (500, 1000, 2500, 5000, 10000, 16000):
        line = f"  {bal:>8,}$"
        for L in lev_tiers:
            v = margin_run(float(bal), L) * 100
            tag = "OK" if v <= 40 else ("TIGHT" if v <= 80 else "CALL")
            line += f"{v:>7.0f}%{tag:<4}"
        print(line)
    print("\n  OK = comfortable, TIGHT = survivable but a losing streak pins you,")
    print("  CALL = the broker stops you out before the strategy's own risk limit does.")
    print("  Margin is nearly independent of balance (lots scale with it), so leverage -")
    print("  not account size - is what decides this row.")

    # --- floor 3: degradation sweep ---
    print("\n  Floor 3 - ACTUAL PERFORMANCE BY BALANCE (full replay, 0.50% risk, TEST)")
    print("  Skipped% is the fraction of signals the EA cannot take because 0.01 lots would")
    print("  risk more than 0.50% of the balance.\n")
    print(f"  {'balance':>9} {'skipped':>8} {'trades':>7} {'mean %/mo':>10} {'median':>8} "
          f"{'worst mo':>9} {'maxDD':>7} {'total':>9}")
    print("  " + "-" * 76)
    for bal in (250, 500, 750, 1000, 1500, 2500, 5000, 10000):
        rc = bal * RISK
        skipped = 0
        for t in uni:
            lpl = t.stop_pips * V.SPECS[t.sym][1] + V.COMM_RT
            if int((rc / lpl) / V.VOL_STEP) * V.VOL_STEP < V.VOL_MIN:
                skipped += 1
        V.ACCOUNT = float(bal)
        res = PA.replay_personal(uni, RISK, mode="initial", max_conc=EA_CONC,
                                 cap_day=EA_DAY, breaker=EA_BREAKER)
        # A0 is a DEFAULT ARGUMENT on month_stats, so Python bound it to V.ACCOUNT at import
        # time ($2,500). Passing it explicitly is not optional - without it every row is
        # silently scaled by bal/2500 and mean %/mo stops reconciling with total return.
        _, rets = PA.month_stats(res, A0=float(bal))
        mean = sum(rets) / len(rets) * 100
        med = sorted(rets)[len(rets)//2] * 100
        worst = min(rets) * 100
        print(f"  {bal:>8,}$ {skipped/len(uni)*100:>7.1f}% {len(uni)-skipped:>7,} "
              f"{mean:>+9.2f}% {med:>+7.2f}% {worst:>+8.2f}% {res['mdd']*100:>6.1f}% "
              f"{res['total_ret']*100:>+8.0f}%")

    # --------------------------------------------------------------- PART 3
    print("\n" + "=" * 108)
    print("PART 3 - REAL BROKER QUOTES, WEIGHTED FOR WHEN THIS STRATEGY ACTUALLY ENTERS")
    print("=" * 108)
    print("""
  Headline spreads are measured during London/NY peak hours. This strategy does not trade
  then. Entries by UTC hour on the held-out TEST set:

        21:00  368 entries (30.7%)   <-- the daily rollover
        22:00  161 entries (13.4%)
        12:00   83 entries  (6.9%)
        20:00   83 entries  (6.9%)
        all other hours: 503 entries (42.0%)

  43.8% of entries fall in the server 20:00-00:59 rollover/close window. Published 30-day
  broker tests measure EURUSD at 0.1 pips in London but 1.2 pips average and 3.1 max across
  the 21:00-22:00 rollover, with 0% of time at zero. So a broker's headline number describes
  the session that carries only ~42% of these trades.

  Below, each broker is modelled with its published RAW-account quote for peak hours, its
  actual commission, and a rollover multiplier applied to entries in UTC 21:00-22:59.
  Cells marked ~ are interpolated from the same broker's other pairs, not measured.
""")

    # published RAW-account averages, independent 30-day tests + compareforexbrokers 2026.
    # "~" = interpolated from that broker's measured pairs, not directly published.
    BROKERS = {
        # flat=True means the cost model does not vary by hour, so no rollover widening
        # applies. That is the validated backtest: it charges 0.55x standard spread on every
        # trade regardless of session, which is why it is the reference row.
        "backtest assumption (flat)": dict(comm=7.00, flat=True, sprd={
            "EURGBP": 0.77, "AUDUSD": 0.66, "NZDUSD": 0.88, "USDCAD": 0.99,
            "USDCHF": 0.77, "EURJPY": 0.88, "GBPJPY": 1.10, "XAUUSD": 1.54}),
        "IC Markets Raw": dict(comm=7.00, flat=False, sprd={
            "EURGBP": 0.27, "AUDUSD": 0.23, "NZDUSD": 0.30, "USDCAD": 0.45,
            "USDCHF": 0.57, "EURJPY": 0.30, "GBPJPY": 0.80, "XAUUSD": 0.80}),
        "Fusion Markets Zero": dict(comm=4.50, flat=False, sprd={
            "EURGBP": 0.39, "AUDUSD": 0.09, "NZDUSD": 0.30, "USDCAD": 0.23,
            "USDCHF": 0.41, "EURJPY": 0.48, "GBPJPY": 0.90, "XAUUSD": 1.50}),
        "Pepperstone Razor": dict(comm=7.00, flat=False, sprd={
            "EURGBP": 0.25, "AUDUSD": 0.19, "NZDUSD": 0.40, "USDCAD": 0.50,
            "USDCHF": 0.39, "EURJPY": 1.15, "GBPJPY": 0.80, "XAUUSD": 1.00}),
        "Tickmill Pro": dict(comm=4.00, flat=False, sprd={
            "EURGBP": 0.40, "AUDUSD": 0.37, "NZDUSD": 0.50, "USDCAD": 0.50,
            "USDCHF": 0.52, "EURJPY": 0.70, "GBPJPY": 1.00, "XAUUSD": 1.50}),
        # FXCC ECN XL ("ZERO"): spread-only, NO commission. Spreads are the LIVE quotes
        # published on myfxbook's FXCC feed (broker id 5191), sampled from real accounts -
        # EURGBP 0.9, AUDUSD 0.6, NZDUSD 0.7, USDCAD 0.5, USDCHF 0.5, EURJPY 1.3,
        # GBPJPY 1.3, and XAUUSD 16 cents = 1.6 pips at this model's 0.10 gold pip.
        # A single snapshot is noisier than a 30-day average, so this row is CONSERVATIVE:
        # daytrading.com's FXCC averages are tighter still (EURGBP 0.3-0.6, gold 12-20c).
        "FXCC ECN XL (myfxbook live)": dict(comm=0.00, flat=False, sprd={
            "EURGBP": 0.90, "AUDUSD": 0.60, "NZDUSD": 0.70, "USDCAD": 0.50,
            "USDCHF": 0.50, "EURJPY": 1.30, "GBPJPY": 1.30, "XAUUSD": 1.60}),
    }

    def apply_costs(comm, sprd, flat, roll_mult):
        """Rewrite cost_R on every trade for a given broker profile and rollover widening."""
        for t in uni:
            pip, pv, _ = V.SPECS[t.sym]
            sp = sprd[t.sym]
            if not flat:
                hr = datetime.fromtimestamp(t.ets / 1000, tz=timezone.utc).hour
                if hr in (21, 22):
                    sp *= roll_mult
            t.cost_R = (sp * pv + comm) / (t.stop_pips * pv + comm)

    def monthly():
        V.ACCOUNT = 2500.0
        r = PA.replay_personal(uni, RISK, mode="initial", max_conc=EA_CONC,
                               cap_day=EA_DAY, breaker=EA_BREAKER)
        _, rets = PA.month_stats(r, A0=2500.0)
        return r, sum(rets) / len(rets) * 100

    def enet():
        return sum(t.R - t.cost_R for t in uni) / len(uni)

    print("  A. PEAK-HOUR QUOTES ONLY (no rollover widening) - the flattering view")
    print(f"\n  {'broker':<28} {'comm RT':>8} {'E_net':>8} {'mean %/mo':>10} {'maxDD':>7} {'total':>8}")
    print("  " + "-" * 74)
    ref = None
    for name, b in BROKERS.items():
        apply_costs(b["comm"], b["sprd"], b["flat"], 1.0)
        e = enet(); r, m = monthly()
        if ref is None:
            ref = (e, m)
        print(f"  {name:<28} {b['comm']:>7.2f}$ {e:>+7.3f}R {m:>+9.2f}% "
              f"{r['mdd']*100:>6.1f}% {r['total_ret']*100:>+7.0f}%")

    print("\n  B. WITH ROLLOVER WIDENING on the 44% of entries in UTC 21:00-22:59")
    print("     The multiplier is an ASSUMPTION, not a measurement: published 30-day tests")
    print("     show EURUSD at 0.1 pips in London vs 1.2 avg / 3.1 max across the rollover")
    print("     (~12x). Sweeping it is the only honest way to show the exposure.\n")
    print(f"  {'broker':<28}" + "".join(f"{('x'+str(int(m))):>10}" for m in (2, 4, 8, 12)))
    print("  " + "-" * 68)
    for name, b in BROKERS.items():
        line = f"  {name:<28}"
        for rm in (2, 4, 8, 12):
            apply_costs(b["comm"], b["sprd"], b["flat"], rm)
            line += f"{enet():>+9.3f}R"
        print(line)
    print("\n  Same, as mean %/month:")
    print(f"  {'broker':<28}" + "".join(f"{('x'+str(int(m))):>10}" for m in (2, 4, 8, 12)))
    print("  " + "-" * 68)
    for name, b in BROKERS.items():
        line = f"  {name:<28}"
        for rm in (2, 4, 8, 12):
            apply_costs(b["comm"], b["sprd"], b["flat"], rm)
            _, m = monthly()
            line += f"{m:>+9.2f}%"
        print(line)

    # restore the validated flat cost model for everything downstream
    b0 = BROKERS["backtest assumption (flat)"]
    apply_costs(b0["comm"], b0["sprd"], True, 1.0)
    assert abs(enet() - tot_n) < 1e-12, f"cost_R not restored: {enet()} vs {tot_n}"

    print(f"""
  What this says:
    * On peak-hour quotes alone every real raw account beats the backtest assumption,
      because the model charged 0.55x standard spread on ALL pairs and real raw quotes are
      2-7x tighter than that on most of this universe.
    * That advantage shrinks or reverses once the rollover is priced, because 44% of entries
      land in it. At a realistic ~8-12x widening the strategy's expectancy is materially
      below the published backtest figure, not above it.
    * Commission differences ($4.00-$7.00 round turn) matter far less than rollover spread,
      because the stops are wide: $3/lot is under 1% of 1R on most trades here.
    * The decisive number is therefore each broker's 21:00-22:00 UTC spread on EURGBP,
      NZDUSD and XAUUSD - not its homepage headline. EA_SIGNAL_DUMP.mq5 on a demo account
      for two weeks measures it directly; the CSV has the entry timestamp on every row.
""")

    # --------------------------------------------------------------- PART 4
    print("\n" + "=" * 108)
    print("PART 4 - WHAT \"% PER MONTH\" ACTUALLY MEANS HERE")
    print("=" * 108)
    print("""
  Two sizing modes produce very different headlines from the SAME trades, and the second is
  where misleading numbers come from.

    fixed      risk 0.50% of the STARTING balance forever. Linear. Monthly % is a stable rate
               on money actually at risk, so it can be read directly.
    compounded risk 0.50% of CURRENT equity. Positions grow as the account grows. Monthly %
               measured against the INITIAL balance then rises purely because the account is
               bigger, so that column must NOT be averaged and quoted as a monthly return.
               The meaningful figures are the geometric growth rate and, per month, the
               return on the equity that existed when that month started.
""")
    V.ACCOUNT = 2500.0
    print(f"  {'mode':<12} {'mean/mo':>9} {'median':>8} {'worst':>8} {'maxDD':>7} "
          f"{'final':>11} {'total':>8}")
    print("  " + "-" * 68)
    out = {}
    for mode in ("initial", "equity"):
        r = PA.replay_personal(uni, RISK, mode=mode, max_conc=EA_CONC,
                               cap_day=EA_DAY, breaker=EA_BREAKER)
        out[mode] = r
        ks, _ = PA.month_stats(r, A0=2500.0)
        if mode == "initial":
            # % of initial IS % of current equity when sizing never changes
            show = [r["months"][k] / 2500.0 for k in ks]
        else:
            show, bal = [], 2500.0
            for k in ks:
                pnl = r["months"][k]
                show.append(pnl / bal if bal > 0 else 0.0)
                bal += pnl
        out[mode + "_show"] = show
        print(f"  {mode:<12} {sum(show)/len(show)*100:>+8.2f}% "
              f"{sorted(show)[len(show)//2]*100:>+7.2f}% {min(show)*100:>+7.2f}% "
              f"{r['mdd']*100:>6.1f}% {r['final']:>10,.0f}$ {r['total_ret']*100:>+7.0f}%")

    n_mo = len(out["initial_show"])
    geo = ((out["equity"]["final"] / 2500.0) ** (1.0 / n_mo) - 1) * 100
    eq = out["equity_show"]
    losing = sum(1 for x in eq if x < 0) / len(eq) * 100
    fix = out["initial_show"]
    print(f"""
  {n_mo} months of held-out TEST data, EA at its shipped gates (every signal, -3R daily
  breaker), 0.50% risk, 8-pair universe, no prop-firm caps.

    fixed sizing      {sum(fix)/n_mo*100:+.2f}%/month, $2,500 -> ${out['initial']['final']:,.0f} ({out['initial']['total_ret']*100:+.0f}%), maxDD {out['initial']['mdd']*100:.1f}%,
                      worst month {min(fix)*100:+.1f}%, {sum(1 for x in fix if x<0)/len(fix)*100:.0f}% of months negative
    compounded sizing {geo:+.2f}%/month GEOMETRIC on current equity, $2,500 -> ${out['equity']['final']:,.0f}
                      ({out['equity']['total_ret']*100:+.0f}%), maxDD {out['equity']['mdd']*100:.1f}%, worst month {min(eq)*100:+.1f}%,
                      {losing:.0f}% of months negative

  So a ~10%/month target IS inside what this strategy demonstrated on held-out data - but
  only under compounding, and the price of compounding is that the drawdown roughly doubles
  ({out['equity']['mdd']*100:.1f}% vs {out['initial']['mdd']*100:.1f}%), because positions are largest exactly when the account is at its
  peak. On fixed sizing the honest rate is about {sum(fix)/n_mo*100:.0f}% of the STARTING balance per month,
  and it does not grow.

  Both are gross of swap, which this model does not charge. personal_account_analysis.py
  measures 0.772 nights per trade and shows 0.10R/night costing roughly 1.3 points of monthly
  return - a real, if second-order, deduction that a broker's swap table decides.
""")

    V.ACCOUNT = 2500.0
    print("\n" + "=" * 108)
    print("BOTTOM LINE")
    print("=" * 108)
    print(f"""
  0. JURISDICTION COMES FIRST. For a person resident in India this strategy cannot be run
     legally: all 8 pairs are non-INR OTC instruments, every broker that quotes them tightly
     is on the RBI Alert List, MT4/MT5 are listed too, and LRS cannot fund it. Nothing below
     changes that. See Part 0.

  1. BROKER, on cost alone. Raw/ECN beats standard on {raw_wins}/{len(UNIVERSE)} pairs - the wide stops make
     1R large in dollars, so a flat commission is a smaller slice of it than the spread. But
     commission is the SECOND-order choice: $4.00 vs $7.00 round turn moves expectancy by less
     than a 2x change in rollover spread does, and Tickmill's low commission does not save it
     from being worst at 12x rollover widening.

     Choose on measured ROLLOVER spread, because 43.8% of entries land in UTC 21:00-00:59 and
     30.7% in the single hour UTC 21:00. Per-pair break-even ceilings at the validated cost
     model, i.e. the widest quote that still has positive expectancy:
""")
    for s_, std, raw, med, cost, eg, en, be, hr, n, dead in sorted(rows, key=lambda r: r[8]):
        if dead:
            print(f"       {s_:<8} no ceiling - negative gross edge on TEST at any spread")
        else:
            print(f"       {s_:<8} break-even {be:>6.2f} pips round turn ({hr:.1f}x the validated raw quote)")
    print(f"""
     XAUUSD is the outlier in both directions: only 3.2% of 1R goes to cost because its stops
     are ~93 pips, so spread barely matters - but its GROSS edge on TEST is negative
     (-0.187R), so no broker makes it work. It was selected on TRAIN (+0.319R) and decayed.

  2. MINIMUM BALANCE. Three floors, and they are not the same constraint:

     a) Lot granularity - the hard one. lots = floor(risk / loss_per_lot / 0.01) x 0.01 and
        the EA skips the trade below 0.01 lots, so a trade needs balance >= 2 x loss_per_lot.
        Excluding XAUUSD the worst trade needs ${2*fx_max:,.0f}. XAUUSD alone raises that to
        ${2*global_max:,.0f}, {global_max/fx_max:.0f}x, because a gold stop is ~93 pips on a 100oz contract.
        Skipped trades are not random - they are the wide-stop ones - so a small account does
        not run the validated strategy, it runs a biased subset of it.

     b) Margin - decided by LEVERAGE, not balance. The stream reaches 9 concurrent positions
        and 13 trades in a day. Peak margin as a share of equity is roughly constant across
        balances (lots scale with balance), and at 1:100 it is ~82%: a margin call arrives
        before the strategy's own risk limit does. 1:200 is tight, 1:500 is comfortable. At
        the 1:30 EU/UK retail cap it is ~274% and simply cannot be run as validated.

     c) Drawdown tolerance. Fixed sizing on TEST: maxDD ~12%, worst month ~-11%, about a
        quarter of months negative. Compounded: ~23% maxDD.

  3. WHAT THE DATA SUPPORTS. At 0.50% risk on held-out TEST, the EA at its shipped gates
     (every signal, -3R daily breaker) returned +12.60%/month of the STARTING balance on fixed
     sizing, and +11.94%/month geometric compounded. A ~10%/month target is inside that - but
     only with compounding, which doubles the drawdown, and only if your broker's rollover
     spread is near the published peak quotes rather than 8-12x wider. That single unmeasured
     assumption is worth roughly +5%/month of the headline, which is why Part 3 sweeps it
     instead of picking a value.
""")

if __name__ == "__main__":
    main()
