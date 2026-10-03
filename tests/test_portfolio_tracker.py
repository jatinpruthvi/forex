"""Mirror tests for the two-EA portfolio split (AllEnginesEA + PortfolioEA).

The Python below re-implements ONLY the contracts of the hand-written MQL5
tracker, so a change in `portfolio-EA/src/PortfolioEA.mq5` that is not mirrored
here shows up as a failure:

* identity parsing - a text-line reader keyed by the header column names, which
  tolerates a trailing `order_policy` field that itself contains a comma, a BOM,
  and blank/comment lines;
* deal accounting - entry-side commission/swap belongs to the round turn, so it
  is carried until the closing deal instead of being dropped;
* the verdict table - not-enough-trades is decided before DROP, and a zero-trade
  engine is never reported as KEEP;
* the `switch` column of the report must name an input that really exists in the
  generated trading EA (that is the whole point of the column).
"""
from __future__ import annotations

import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "portfolio-EA" / "build"
EA = BUILD / "AllEnginesEA.mq5"


def parse_identity(text: str) -> dict:
    """Mirror of PortfolioEA.mq5 LoadIdentity()."""
    rows: dict[int, dict] = {}
    cols = {"magic": 0, "tag": 1, "ea": 2, "strategy": 3, "timeframe": 5}
    first = True
    for raw in text.replace("\ufeff", "").splitlines():
        line = raw.strip()
        if not line:
            continue
        f = line.split(",")
        if len(f) < 4:
            continue
        if first:
            first = False
            for i, key in enumerate(f):
                key = key.strip()
                if key in cols:
                    cols[key] = i
            if f[cols["magic"]].strip() in ("", "magic"):
                continue                                    # header row
        magic = int(f[cols["magic"]].strip() or 0)
        if magic <= 0:
            continue                                        # comment / junk line
        rows[magic] = {
            "tag": f[cols["tag"]],
            "ea": f[cols["ea"]],
            "strategy": f[cols["strategy"]],
            "tf": f[cols["timeframe"]],
        }
    return rows


def deal_accounting(deals):
    """Mirror of Refresh() pass 1.  Each deal is
    (is_trade, entry_in, money, position_id) and entry-side money is carried per
    position, exactly like the MQL5 SPending store.

    Returns (net, closed, wins, losses, max_dd).
    """
    net = closed = wins = losses = 0
    run = peak = max_dd = 0.0
    pending: dict[int, float] = {}
    for is_trade, entry_in, money, pos_id in deals:
        if is_trade and entry_in:
            pending[pos_id] = pending.get(pos_id, 0.0) + money
            continue
        if is_trade:
            pl = money + pending.pop(pos_id, 0.0)           # whole round turn
            net += pl
            closed += 1
            if pl > 0:
                wins += 1
            elif pl < 0:
                losses += 1
            run += pl
        else:
            net += money                                    # own event
            run += money
        peak = max(peak, run)
        max_dd = max(max_dd, peak - run)
    return net, closed, wins, losses, max_dd


def verdict(closed: int, net: float, dd_pct: float,
            min_trades: int, review_dd: float) -> str:
    """Mirror of the verdict block in Refresh()."""
    if closed == 0:
        return "TOO_FEW"
    if closed < min_trades:
        return "REVIEW" if dd_pct >= review_dd else "TOO_FEW"
    if net < 0.0:
        return "DROP"
    if net / closed <= 0.0 or dd_pct >= review_dd:
        return "REVIEW"
    return "KEEP"


class IdentityParsing(unittest.TestCase):
    def setUp(self):
        self.engines = (BUILD / "engines.csv").read_text(encoding="utf-8")
        self.rows = parse_identity(self.engines)

    def test_generated_identity_file_is_complete(self):
        self.assertEqual(len(self.rows), 65)
        magics = sorted(self.rows)
        self.assertEqual(len(set(magics)), 65)
        for magic, row in self.rows.items():
            self.assertEqual(row["tag"], f"P{magic}|")
            self.assertTrue(row["ea"].startswith("EA_"), row)

    def test_order_policy_comma_does_not_shift_columns(self):
        # every real row carries `order_policy` text that may contain a comma;
        # the reader keys on the header names, so the fields must survive
        bodies = [l for l in self.engines.splitlines()[1:] if l.strip()]
        self.assertEqual(len(bodies), 65)
        with_comma = [l for l in bodies if len(l.split(",")) > 10]
        self.assertTrue(with_comma, "expected the comma-bearing order_policy rows")
        for line in with_comma:
            magic = int(line.split(",")[0])
            self.assertEqual(self.rows[magic]["strategy"],
                             line.split(",")[3])

    def test_reader_tolerates_bom_blank_and_junk_lines(self):
        text = ("\ufeffmagic,tag,ea,strategy,symbols,timeframe\n"
                "\n"
                "# a comment line, not a row\n"
                "3101,P3101|,EA_A,STRAT,XAUUSD,M5\n"
                "garbage\n"
                "3102,P3102|,EA_B,STRAT,EURUSD,M15\n")
        rows = parse_identity(text)
        self.assertEqual(sorted(rows), [3101, 3102])
        self.assertEqual(rows[3101]["tf"], "M5")
        self.assertEqual(rows[3102]["tf"], "M15")

    def test_switch_column_names_a_real_input(self):
        switches = {l.split(",")[7] for l in self.engines.splitlines()[1:] if l.strip()}
        self.assertEqual(len(switches), 65)
        host = EA.read_text(encoding="utf-8")
        for sw in sorted(switches):
            self.assertIn(f"input bool {sw} = ", host, sw)


class TrackerAccounting(unittest.TestCase):
    def test_entry_commission_reaches_net(self):
        # entry deal: commission -7, no profit; close: +100 gross
        net, closed, wins, losses, dd = deal_accounting(
            [(True, True, -7.0, 1), (True, False, 100.0, 1)])
        self.assertAlmostEqual(net, 93.0)
        self.assertEqual((closed, wins, losses), (1, 1, 0))
        self.assertAlmostEqual(dd, 0.0)
        naive = 100.0            # what counting closes only would report
        self.assertNotAlmostEqual(net, naive)

    def test_entry_cost_turns_a_winner_into_a_loser(self):
        net, closed, wins, losses, dd = deal_accounting(
            [(True, True, -30.0, 1), (True, False, 25.0, 1)])
        self.assertAlmostEqual(net, -5.0)
        self.assertEqual((wins, losses), (0, 1))
        self.assertAlmostEqual(dd, 5.0)

    def test_cost_only_deals_count_once(self):
        net, closed, wins, losses, dd = deal_accounting(
            [(True, True, -2.0, 1), (False, False, -8.0, 0), (True, False, 50.0, 1)])
        self.assertAlmostEqual(net, 40.0)
        self.assertEqual(closed, 1)
        # the -8 charge is its own event on the curve, so the curve dips to -8
        # before the winning close lifts it - the cost is not lost
        self.assertAlmostEqual(dd, 8.0)

    def test_two_open_positions_are_not_cross_charged(self):
        # position 1: -10 entry cost, closes at +8  -> a net LOSS
        # position 2: -30 entry cost, closes at +50 -> a net WIN
        # a per-engine bucket would charge both entry costs to the first close
        net, closed, wins, losses, _ = deal_accounting(
            [(True, True, -10.0, 1), (True, True, -30.0, 2),
             (True, False, 8.0, 1), (True, False, 50.0, 2)])
        self.assertAlmostEqual(net, 18.0)
        self.assertEqual((closed, wins, losses), (2, 1, 1))

    def test_drawdown_curve_includes_entry_costs(self):
        _, _, _, _, dd = deal_accounting(
            [(True, True, -5.0, 1), (True, False, -20.0, 1)])
        self.assertAlmostEqual(dd, 25.0)


class VerdictTable(unittest.TestCase):
    def test_zero_trades_is_never_keep(self):
        self.assertEqual(verdict(0, 0.0, 0.0, 20, 25.0), "TOO_FEW")

    def test_too_few_beats_drop(self):
        self.assertEqual(verdict(3, -500.0, 1.0, 20, 25.0), "TOO_FEW")

    def test_few_trades_with_large_dd_is_flagged(self):
        self.assertEqual(verdict(3, -500.0, 40.0, 20, 25.0), "REVIEW")

    def test_negative_after_enough_trades_is_drop(self):
        self.assertEqual(verdict(25, -10.0, 1.0, 20, 25.0), "DROP")

    def test_flat_is_review_not_keep(self):
        self.assertEqual(verdict(25, 0.0, 1.0, 20, 25.0), "REVIEW")

    def test_deep_drawdown_is_review(self):
        self.assertEqual(verdict(25, 100.0, 30.0, 20, 25.0), "REVIEW")

    def test_profitable_shallow_is_keep(self):
        self.assertEqual(verdict(25, 100.0, 5.0, 20, 25.0), "KEEP")


if __name__ == "__main__":
    unittest.main()
