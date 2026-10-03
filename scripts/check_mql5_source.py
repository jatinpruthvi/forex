#!/usr/bin/env python3
"""Static structural checker for the MQL5_Master sources.

There is no MetaEditor in CI here, so this mirrors the repository's existing
"source contract" tests for TRIAD_R_HS / TRIAD_SCREEN: it pins the properties a
file must have to be a valid, isolated EA and catches the classic generation
defects (unbalanced blocks, missing handlers, duplicate magics, MQL4
contamination, calls into the shared engine that do not exist, ...).

Usage:  python3 scripts/check_mql5_source.py [paths...]
Exit code 0 = clean, 1 = findings.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INCLUDES = ROOT / "MQL5_Master" / "Include"
MASTER = ROOT / "MQL5_Master"
ADDITIONAL = ROOT / "MQL5_Master" / "Experts" / "additionalEAs"

MQL4_ONLY = [
    "AccountBalance(", "AccountEquity(", "AccountFreeMargin(", "AccountMargin(",
    "MarketInfo(", "OrderClose(", "OrderSend(", "OrdersTotal(",
    "iCustom(", "ObjectCreate(", "GetTickCount(",  # GetTickCount IS MQL5 but flagged separately below
]
# functions that are MQL4-only or that we deliberately forbid in the new EAs
FORBIDDEN = [
    r"\bAccountBalance\s*\(", r"\bAccountEquity\s*\(", r"\bAccountFreeMargin\s*\(",
    r"\bMarketInfo\s*\(", r"\bOrderClose\s*\(", r"\bOrderModify\s*\(",
    r"\bOrderSelect\s*\(",
    r"\btry\b", r"\bcatch\b", r"#property\s+strict",
    r"(?<![\w.])Symbol\s*\(\s*\)",   # MQL4 Symbol(); MQL5 uses _Symbol
    r"\bBid\b(?!\s*[.(])", r"\bAsk\b(?!\s*[.(])",
]
BUILTIN_OK = {
    # MQL5 API roots we rely on (used to whitelist calls)
    "iATR", "iMA", "iRSI", "iADX", "iBands", "iTime", "iClose", "iOpen", "iHigh",
    "iLow", "iBarShift", "CopyBuffer", "CopyRates", "CopyTime", "ArraySetAsSeries",
    "ArrayResize", "ArraySize", "TimeToStruct", "StructToTime", "TimeCurrent",
    "TimeTradeServer", "TimeLocal", "TimeToString", "StringFormat", "StringSplit",
    "StringLen", "StringFind", "StringSubstr", "StringTrimLeft", "StringTrimRight",
    "StringToTime", "StringToDouble", "StringToInteger", "StringGetCharacter",
    "IntegerToString", "DoubleToString", "PrintFormat", "Print", "Comment",
    "MathAbs", "MathMax", "MathMin", "MathFloor", "MathRound", "MathSqrt",
    "MathPow", "MathCeil", "SymbolInfoDouble", "SymbolInfoInteger",
    "SymbolInfoString", "SymbolInfoTick", "SymbolSelect", "PositionsTotal",
    "PositionGetTicket", "PositionSelectByTicket", "PositionGetDouble",
    "PositionGetInteger", "PositionGetString", "OrdersTotal", "OrderGetTicket",
    "OrderGetDouble", "OrderGetInteger", "OrderGetString", "HistorySelect",
    "HistoryDealsTotal", "HistoryDealGetTicket", "HistoryDealGetDouble",
    "HistoryDealGetInteger", "HistoryDealGetString", "HistoryDealsTotal",
    "AccountInfoDouble", "AccountInfoInteger", "AccountInfoString",
    "TerminalInfoInteger", "MQLInfoInteger", "OrderCalcMargin", "OrderCalcProfit",
    "OrderCheck", "FileOpen", "FileClose", "FileReadString", "FileWrite",
    "FileSeek", "FileTell", "FileIsEnding", "NormalizeDouble", "GetLastError",
    "ResetLastError", "IndicatorRelease", "Sleep", "EventKillTimer",
    "EventSetTimer", "TesterStatistics", "EnumToString", "DoubleToStr",
    "EnumToInteger", "ZeroMemory", "CheckPointer", "GlobalVariableGet",
    "GlobalVariableSet", "GlobalVariableCheck", "GlobalVariableDel",
    "ChartRedraw", "SendNotification", "ObjectDelete", "ObjectFind",
}

ALLOWED_OVERRIDES = {"Configure", "BuildPlan", "Manage", "AllowTrading",
                     "LotsMultiplier", "AllowMultipleOnSymbol", "OnInitStrategy",
                     "OnDeinitStrategy", "RankSetup", "Reset"}


def strip_noise(src: str) -> str:
    """Remove comments and string/char literals so structural scans are honest."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
        elif c in "\"'":
            quote = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            out.append("S")      # placeholder keeps `return "";` well formed
        else:
            out.append(c)
            i += 1
    return "".join(out)


def balanced(src: str) -> list[str]:
    """Check (), {} and [] balance outside comments/strings."""
    problems = []
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "}": "{", "]": "["}
    line = 1
    for ch in src:
        if ch == "\n":
            line += 1
            continue
        if ch in "({[":
            stack.append((ch, line))
        elif ch in ")}]":
            if not stack or stack[-1][0] != pairs[ch]:
                problems.append(f"unbalanced '{ch}' at line {line}")
                return problems
            stack.pop()
    for ch, ln in stack:
        problems.append(f"unclosed '{ch}' opened at line {ln}")
    return problems


def check_returns(src: str) -> list[str]:
    """Catch `return` without a value in a non-void function (rough heuristic)."""
    problems = []
    cur_ret = None
    for m in re.finditer(r"^\s*(?:virtual\s+)?([A-Za-z_][\w:<>*& ]*?)\s+([A-Za-z_]\w*)\s*\([^;{]*\)\s*(?:const)?\s*\{", src, re.M):
        ret = m.group(1).strip()
        if ret in ("if", "while", "for", "switch", "else"):
            continue
        cur_ret = ret
        # scan the function body for a bare return;
        body_start = m.end()
        depth = 1
        i = body_start
        while i < len(src) and depth > 0:
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
            i += 1
        body = src[body_start:i]
        if ret != "void" and re.search(r"\breturn\s*;", body):
            problems.append(f"'{m.group(2)}' returns {ret} but has a bare 'return;'")
    return problems


def collect_callables(paths: list[Path]) -> set[str]:
    """Names of functions/methods defined across the given files."""
    defined: set[str] = set(BUILTIN_OK)
    pattern = re.compile(
        r"^\s*(?:virtual\s+|static\s+)?(?:[A-Za-z_][\w:<>*&]*\s+)+"
        r"([A-Za-z_]\w*)\s*\([^;{)]*\)\s*(?:const|override)?\s*\{", re.M)
    for p in paths:
        src = strip_noise(p.read_text(encoding="utf-8", errors="replace"))
        for m in pattern.finditer(src):
            defined.add(m.group(1))
        # class declarations
        for m in re.finditer(r"\b(?:class|struct)\s+([A-Za-z_]\w*)", src):
            defined.add(m.group(1))
        # enum values
        for m in re.finditer(r"enum\s+[A-Za-z_]\w*\s*\{([^}]*)\}", src, re.S):
            for v in m.group(1).split(","):
                name = v.split("=")[0].strip()
                if name:
                    defined.add(name)
    return defined


def check_file(path: Path, defined: set[str], is_ea: bool) -> list[str]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    src = strip_noise(raw)
    problems = balanced(src)
    problems += check_returns(src)

    for pat in FORBIDDEN:
        for m in re.finditer(pat, src):
            line = src[:m.start()].count("\n") + 1
            problems.append(f"MQL4/forbidden pattern '{m.group(0).strip()}' at line {line}")

    if is_ea:
        for need in ("int OnInit(", "void OnTick(", "void OnDeinit("):
            if need not in src:
                problems.append(f"missing event handler {need}")
        if "EACommon.mqh" not in raw:
            problems.append("does not include the shared engine (EACommon.mqh)")
        if not re.search(r"class\s+C\w+\s*:\s*public\s+CEAStrategy", src):
            problems.append("no CEAStrategy-derived strategy class")
        for need in ("void Configure(", "bool BuildPlan("):
            if need not in src:
                problems.append(f"strategy class missing {need}")
        if "EA_Init(" not in src or "EA_Tick(" not in src or "EA_Deinit(" not in src:
            problems.append("event handlers do not delegate to the engine")
        m = re.search(r"input\s+ulong\s+InpMagicNumber\s*=\s*(\d+)", raw)
        if not m:
            problems.append("missing InpMagicNumber input")

    #--- input variables must never be assigned (declarations excluded)
    declarations = re.findall(r"^\s*input\s+[A-Za-z_][\w:<>]*\s+Inp\w+\s*=[^;]*;",
                              raw, re.M)
    body = src
    for decl in declarations:
        body = body.replace(strip_noise(decl), "", 1)
    for m in re.finditer(r"^\s*input\s+[A-Za-z_][\w:<>]*\s+(Inp\w+)", src, re.M):
        name = m.group(1)
        if re.search(rf"(?<![\w.]){name}\s*(?:=|\+\+|--)(?!=)", body):
            problems.append(f"assignment to input variable {name}")

    #--- every call to our own helper namespace must exist somewhere
    if is_ea:
        for m in re.finditer(r"\b(EA_[A-Za-z_]\w*|Sig[A-Z]\w*)\s*\(", src):
            name = m.group(1)
            if name not in defined:
                line = src[:m.start()].count("\n") + 1
                problems.append(f"call to undefined helper {name}() at line {line}")
    return problems



#--- fields declared in the engine's SEASettings block (used by cfg.<field> checks)
def _settings_fields() -> set[str]:
    core = (INCLUDES / "EACore.mqh").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"struct\s+SEASettings\s*\{(.*?)\n\};", core, re.S)
    if not m:
        return set()
    fields: set[str] = set()
    for line in m.group(1).splitlines():
        line = line.split("//")[0].strip()
        if not line or line.startswith("//"):
            continue
        mm = re.match(r"[\w:]+(?:\s*<[^>]*>)?\s+([^;]+);", line)
        if not mm:
            continue
        for part in mm.group(1).split(","):
            nm = re.match(r"\s*([A-Za-z_]\w*)", part)
            if nm:
                fields.add(nm.group(1))
    return fields


SETTINGS_FIELDS = _settings_fields()


def check_generation_defects(path: Path, raw: str, src: str) -> list[str]:
    """Defects the old checker could not see: bad include paths, unknown cfg
    fields, duplicated inputs and declarations glued onto a // comment."""
    problems: list[str] = []

    # every quoted #include must resolve exactly as MetaEditor would
    for m in re.finditer(r'#include\s+"([^"]+)"', raw):
        inc = m.group(1).replace("\\", "/")
        cand = (path.parent / inc).resolve()
        if not cand.exists():
            # files that live outside MQL5_Master in the repo (the portfolio host,
            # for instance) still point at the terminal's MQL5 tree; the repo
            # mirrors that tree under MQL5_Master, so fall back to it
            stripped = inc
            while stripped.startswith("../"):
                stripped = stripped[3:]
            for alt in (MASTER / inc, MASTER / stripped):
                if alt.exists():
                    cand = alt
                    break
        if not cand.exists():
            problems.append(f"unresolvable #include \"{m.group(1)}\" (-> {cand})")

    # control characters that MetaEditor cannot parse (a leaked regex backref in
    # a template once put 0x01 in front of an input declaration)
    for i, line in enumerate(raw.splitlines(), 1):
        bad = [c for c in line if ord(c) < 32 and c not in "\t"]
        if bad:
            problems.append(f"control character(s) {[hex(ord(c)) for c in bad]} on line {i}")

    # cfg.<field> must exist in SEASettings
    for m in re.finditer(r"\bcfg\s*\.\s*([A-Za-z_]\w*)", src):
        if src[m.end():m.end() + 1] == "(":
            continue                      # method call such as cfg.Reset()
        if SETTINGS_FIELDS and m.group(1) not in SETTINGS_FIELDS:
            line = src[:m.start()].count("\n") + 1
            problems.append(f"unknown SEASettings field cfg.{m.group(1)} at line {line}")

    # no input may be declared twice
    names = re.findall(r"^\s*input\s+[\w\s]+?\s+([A-Za-z_]\w*)\s*=", src, re.M)
    dupes = {n for n in names if names.count(n) > 1}
    for n in sorted(dupes):
        problems.append(f"duplicate input declaration {n}")

    # every input declaration must start its own line (a trailing // comment
    # otherwise swallows the next declaration)
    for m in re.finditer(r"//[^\n]*input\s+[\w\s]+?\s+Inp\w+\s*=", raw):
        line = raw[:m.start()].count("\n") + 1
        problems.append(f"input declaration glued onto a comment at line {line}")
    return problems


def main(argv: list[str]) -> int:
    paths = [Path(a).resolve() if Path(a).is_absolute() else (ROOT / a) for a in argv[1:]]
    if not paths:
        paths = sorted(INCLUDES.glob("*.mqh")) + sorted(ADDITIONAL.glob("*.mq5"))
    defined = collect_callables(sorted(INCLUDES.glob("*.mqh")))

    findings: list[tuple[Path, str]] = []
    magics: dict[int, Path] = {}
    for p in paths:
        is_ea = p.parent == ADDITIONAL or p.name.startswith("EA_")
        for problem in check_file(p, defined, is_ea):
            findings.append((p, problem))
        for problem in check_generation_defects(p, p.read_text(encoding="utf-8", errors="replace"),
                                                strip_noise(p.read_text(encoding="utf-8", errors="replace"))):
            findings.append((p, problem))
        if is_ea:
            m = re.search(r"input\s+ulong\s+InpMagicNumber\s*=\s*(\d+)",
                          p.read_text(encoding="utf-8", errors="replace"))
            if m:
                magic = int(m.group(1))
                if magic in magics:
                    findings.append((p, f"duplicate magic {magic} (also {magics[magic].name})"))
                else:
                    magics[magic] = p

    for p, problem in findings:
        print(f"{p.relative_to(ROOT)}: {problem}")
    print(f"\nchecked {len(paths)} files, {len(magics)} EAs, "
          f"{len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
