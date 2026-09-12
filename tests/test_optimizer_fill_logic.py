"""Regression tests for the 2026-09-12 fill-semantics fixes in
tools/aggressive_optimizer.py (session-7 audit).

Covers:
  B1  same-bar target/stop ambiguity: optimistic / pessimistic / coin modes
  B2  limit fills require a re-touch of the entry level (require_touch=True)
  B3  one account-wide order/position slot (no overlapping trades)
  B4  per-day pip values (JPY/USDCAD/USDCHF/EURGBP) instead of frozen mids
  legacy=True must reproduce the pre-fix behaviour exactly
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta, timezone

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import tools.aggressive_optimizer as m  # noqa: E402


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def bar(minute_offset, o, h, l, c):
    ts = datetime(2024, 6, 3, 8, 0, tzinfo=timezone.utc) + timedelta(minutes=5 * minute_offset)
    return m.Bar(ts, o, h, l, c)


def make_sig(entry=1.1000, stop=1.0990, target=1.1030, direction="long",
             lots=0.10, signal_minute=0):
    sig_bar = bar(signal_minute, entry + 0.0002, entry + 0.0003, entry - 0.0002, entry + 0.0002)
    return dict(direction=direction, entry=entry, stop=stop, target=target,
                lots=lots, bbar=sig_bar, strategy="orb_atr", pv=10.0)


# ---------------------------------------------------------------------------
# B2 — limit re-touch fills
# ---------------------------------------------------------------------------

def test_require_touch_fills_when_price_returns():
    sig = make_sig()  # long, entry 1.1000, stop 1.0990, target 1.1030
    bars = [bar(1, 1.1005, 1.1008, 1.1000, 1.1006),   # touches entry -> fill
            bar(2, 1.1006, 1.1031, 1.1004, 1.1030)]   # reaches target
    t = m.simulate(sig, bars, bar(2, 0, 0, 0, 0).ts + timedelta(minutes=5),
                   "EURUSD", require_touch=True)
    assert t is not None and t.exit_reason == "target"


def test_require_touch_rejects_never_filled_signal():
    sig = make_sig()
    bars = [bar(1, 1.1005, 1.1015, 1.1002, 1.1012),   # never dips to 1.1000
            bar(2, 1.1012, 1.1031, 1.1008, 1.1030)]   # would-be target
    t = m.simulate(sig, bars, bar(2, 0, 0, 0, 0).ts + timedelta(minutes=5),
                   "EURUSD", require_touch=True)
    assert t is None                                    # no trade live


def test_legacy_mode_fills_every_signal():
    sig = make_sig()
    bars = [bar(1, 1.1005, 1.1015, 1.1002, 1.1012),
            bar(2, 1.1012, 1.1031, 1.1008, 1.1030)]
    t = m.simulate(sig, bars, bar(2, 0, 0, 0, 0).ts + timedelta(minutes=5),
                   "EURUSD", require_touch=False)
    assert t is not None and t.exit_reason == "target"  # old optimistic behaviour


def test_exit_scan_starts_at_fill_bar():
    # fill bar itself reaches the target without hitting the stop -> win
    sig = make_sig()
    bars = [bar(1, 1.1004, 1.1031, 1.0995, 1.1030)]     # low < stop, high > target
    t = m.simulate(sig, bars, bar(1, 0, 0, 0, 0).ts + timedelta(minutes=5),
                   "EURUSD", require_touch=True, stop_first=False)
    assert t is not None and t.exit_reason == "target"


# ---------------------------------------------------------------------------
# B1 — same-bar ambiguity modes
# ---------------------------------------------------------------------------

def test_ambiguity_optimistic_books_target():
    sig = make_sig()
    bars = [bar(1, 1.1000, 1.1031, 1.0989, 1.1020)]     # spans both levels
    t = m.simulate(sig, bars, bar(1, 0, 0, 0, 0).ts + timedelta(minutes=5),
                   "EURUSD", stop_first=False)
    assert t.exit_reason == "target"


def test_ambiguity_pessimistic_books_stop():
    sig = make_sig()
    bars = [bar(1, 1.1000, 1.1031, 1.0989, 1.1020)]
    t = m.simulate(sig, bars, bar(1, 0, 0, 0, 0).ts + timedelta(minutes=5),
                   "EURUSD", stop_first=True)
    assert t.exit_reason == "stop"


def test_ambiguity_coin_is_deterministic_and_covers_both():
    sig = make_sig()
    bars = [bar(1, 1.1000, 1.1031, 1.0989, 1.1020)]
    end = bar(1, 0, 0, 0, 0).ts + timedelta(minutes=5)
    r1 = m.simulate(sig, bars, end, "EURUSD", stop_first=None)
    r2 = m.simulate(sig, bars, end, "EURUSD", stop_first=None)
    assert r1.exit_reason == r2.exit_reason             # reproducible
    assert r1.exit_reason in ("stop", "target")


# ---------------------------------------------------------------------------
# B4 — day pip values
# ---------------------------------------------------------------------------

def test_pip_value_constants_for_usd_quote_pairs():
    assert m.pip_value("EURUSD", 1.08) == 10.0
    assert m.pip_value("XAUUSD", 2300.0) == 10.0


def test_pip_value_jpy_scales_with_rate():
    pv148 = m.pip_value("USDJPY", 148.0)
    pv180 = m.pip_value("USDJPY", 180.0)
    assert pv148 == pytest.approx(100000 * 0.01 / 148.0)
    assert pv180 < pv148


def test_pip_value_usdcad_uses_own_close():
    # USDCAD 1.35 -> 10 CAD per pip = $7.41, NOT the old $9.80 constant
    assert m.pip_value("USDCAD", 1.35) == pytest.approx(7.407, abs=0.01)


def test_pip_value_eurgbp_uses_gbpusd_close():
    cache = {"GBPUSD": ({__import__("datetime").date(2024, 6, 3):
                         [bar(0, 1.27, 1.27, 1.27, 1.27)]}, {})}
    pv = m.day_pv("EURGBP", __import__("datetime").date(2024, 6, 3), cache)
    assert pv == pytest.approx(12.70, abs=0.01)


# ---------------------------------------------------------------------------
# B3 — one account-wide slot (synthetic cache, tiny run)
# ---------------------------------------------------------------------------

def _synth_cache():
    """Two symbols, one day, overlapping signal windows -> only one trade."""
    bars_a, bars_b = [], []
    # orb window: 8 bars ~flat (3-pip range); signal bar closes above orb at :45
    for i in range(8):
        bars_a.append(bar(i, 1.1000, 1.1001, 1.0998, 1.1000))
        bars_b.append(bar(i, 1.2500, 1.2501, 1.2498, 1.2500))
    # signal bar (both symbols signal in the same minute -> only first may trade)
    bars_a.append(bar(8, 1.1002, 1.1006, 1.1001, 1.1005))
    bars_b.append(bar(8, 1.2502, 1.2506, 1.2501, 1.2505))
    # then drift up (targets far) so positions stay open past the next signal
    for i in range(9, 40):
        px_a = 1.1005 + 0.0001 * (i - 8)
        px_b = 1.2505 + 0.0001 * (i - 8)
        bars_a.append(bar(i, px_a, px_a + 0.0002, px_a - 0.0002, px_a))
        bars_b.append(bar(i, px_b, px_b + 0.0002, px_b - 0.0002, px_b))
    d = __import__("datetime").date(2024, 6, 3)
    return {"EURUSD": ({d: bars_a}, {d: 0.0010}), "GBPUSD": ({d: bars_b}, {d: 0.0010})}


def test_one_slot_no_overlapping_trades():
    cache = _synth_cache()
    old_lp, old_np = m.LONDON_PAIRS, m.NY_PAIRS
    m.LONDON_PAIRS, m.NY_PAIRS = ["EURUSD", "GBPUSD"], []
    try:
        r = m.run_backtest(cache, "orb_atr", 3.0, 8, 0.25)
    finally:
        m.LONDON_PAIRS, m.NY_PAIRS = old_lp, old_np
    # the NY signal arrives while the London position is open -> skipped
    assert r["signals"] <= 1
    if r["signals"] == 1:
        fills = [t.fill_ts for t in r["all_trades"]]
        exits = [t.exit_ts for t in r["all_trades"]]
        assert all(e >= f for f, e in zip(fills, exits))


def test_legacy_mode_allows_overlap():
    cache = _synth_cache()
    old_lp, old_np = m.LONDON_PAIRS, m.NY_PAIRS
    m.LONDON_PAIRS, m.NY_PAIRS = ["EURUSD", "GBPUSD"], []
    try:
        r = m.run_backtest(cache, "orb_atr", 3.0, 8, 0.25, legacy=True)
    finally:
        m.LONDON_PAIRS, m.NY_PAIRS = old_lp, old_np
    assert r["signals"] == 2    # old behaviour booked both


# ---------------------------------------------------------------------------
# grid/CLI integrity
# ---------------------------------------------------------------------------

def test_run_grid_returns_all_combos():
    cache = _synth_cache()
    old_lp, old_np = m.LONDON_PAIRS, m.NY_PAIRS
    m.LONDON_PAIRS, m.NY_PAIRS = ["EURUSD", "GBPUSD"], []
    try:
        res = m.run_grid(cache)
    finally:
        m.LONDON_PAIRS, m.NY_PAIRS = old_lp, old_np
    assert len(res) == 60
