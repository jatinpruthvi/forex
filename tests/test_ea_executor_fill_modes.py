"""Regression fences for the shared executor's multi-symbol fill-mode routing."""
from __future__ import annotations

import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
SOURCE = (REPO / "MQL5_Master" / "Include" / "EATrade.mqh").read_text(encoding="utf-8")


def method(name: str, start_at: int = 0) -> str:
    start = SOURCE.index(name, start_at)
    opening = SOURCE.index("{", start)
    depth = 0
    for pos in range(opening, len(SOURCE)):
        if SOURCE[pos] == "{":
            depth += 1
        elif SOURCE[pos] == "}":
            depth -= 1
            if depth == 0:
                return SOURCE[start:pos + 1]
    raise AssertionError(f"unterminated method {name}")


class ExecutorFillModeTests(unittest.TestCase):
    def test_market_orders_select_the_actual_order_symbols_fill_mode(self) -> None:
        helper = method("bool SetSymbolFillMode(")
        market = method("bool SendWithRetry(")
        self.assertIn("m_trade.SetTypeFillingBySymbol(sym)", helper)
        self.assertIn("if(!SetSymbolFillMode(sym)) return false;", market)
        self.assertLess(market.index("SetSymbolFillMode(sym)"), market.index("m_trade.Buy(lots, sym"))

    def test_pending_limits_use_return_filling_independent_of_market_symbol_mode(self) -> None:
        limit = method("bool OpenLimit(")
        self.assertIn("m_trade.SetTypeFilling(ORDER_FILLING_RETURN);", limit)
        self.assertLess(limit.index("SetTypeFilling(ORDER_FILLING_RETURN)"),
                        limit.index("m_trade.BuyLimit(lots, price, sym"))
        self.assertNotIn("SetSymbolFillMode(sym)", limit)

    def test_close_paths_select_the_position_symbols_fill_mode(self) -> None:
        partial = method("bool ClosePartial(")
        close = method("bool Close(const ulong ticket")
        self.assertIn("if(!SetSymbolFillMode(sym)) return false;", partial)
        self.assertIn("m_trade.PositionClose(ticket)", partial)
        self.assertIn("m_trade.PositionClosePartial(ticket, part)", partial)
        self.assertIn("if(!SetSymbolFillMode(sym)) return false;", close)
        self.assertLess(close.index("SetSymbolFillMode(sym)"), close.index("m_trade.PositionClose(ticket)"))

    def test_executor_init_does_not_cache_the_chart_symbols_fill_mode(self) -> None:
        init = method("void Init()", SOURCE.index("class CEAExecutor"))
        self.assertNotIn("SetTypeFillingBySymbol(_Symbol)", init)
        self.assertIn("SetTypeFillingBySymbol(sym)", SOURCE)


if __name__ == "__main__":
    unittest.main()
