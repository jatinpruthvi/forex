#!/usr/bin/env python3
"""Condense a strategy markdown document into an implementable digest.

Keeps headings, tables and bullet/numbered lines that carry rules, parameters,
timeframes, numbers or risk words; drops prose paragraphs and math blocks.
"""
from __future__ import annotations
import re, sys
from pathlib import Path

KEEP = re.compile(
    r"(?i)(\d+\s*[%rp]|atr|ema|rsi|adx|bollinger|donchian|vwap|pip|lot|risk|stop|target|entry|"
    r"session|london|new ?york|asian|tokyo|window|breakout|sweep|reclaim|grid|basket|drawdown|"
    r"magic|timeframe|m1|m5|m15|h1|h4|d1|news|spread|kill|flat|trail|partial|limit|market|"
    r"filter|bias|confirm|score|leg|hedge|volatility|volume|range|channel)")
DROP = re.compile(r"^\s*(\$|\\\[|\\\]|```|---|\|?\s*-{3,})")


def digest(path: Path, limit: int = 2600) -> str:
    out: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip()
        if DROP.match(line):
            continue
        if line.startswith("#"):
            out.append(line)
            continue
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(("* ", "- ", "+ ")) or re.match(r"^\d+[.)]\s", stripped) or stripped.startswith("|"):
            if KEEP.search(stripped) or len(stripped) < 120:
                out.append(stripped)
            continue
    text = "\n".join(out)
    if len(text) > limit:
        text = text[:limit] + "\n...[truncated]"
    return text


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        p = Path(arg)
        print(f"\n{'='*78}\n## FILE: {p}\n{'='*78}")
        print(digest(p))
