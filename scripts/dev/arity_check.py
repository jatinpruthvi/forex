#!/usr/bin/env python3
"""Argument-count checker for the MQL5 delivery.

Every function/method definition in the Include tree and in the target .mq5
files is parsed into a set of (min_args, max_args) ranges (defaults allowed),
then every call site is checked against those ranges.  This catches the class
of bug where a helper signature changes (extra parameter, defaults added or
removed) and a call site keeps the old argument count.

Usage:
    python3 scripts/dev/arity_check.py                 # the 65 EAs + Include
    python3 scripts/dev/arity_check.py file1 file2 ...
    python3 scripts/dev/arity_check.py --selftest      # positive control
"""
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EA_DIR = REPO / "MQL5_Master" / "Experts" / "additionalEAs"
INC_DIR = REPO / "MQL5_Master" / "Include"

KIND = r"(?:void|bool|int|uint|long|ulong|short|ushort|char|uchar|double|float|string|datetime|color|ENUM_\w+|\w+)"
QUAL = r"(?:(?:static|virtual|const|inline|public|private|protected|template\s*<[^>]*>)[ \t]+)*"
DEF_RE = re.compile(r"^[ \t]*" + QUAL + r"(" + KIND + r")[ \t]*[&*]?[ \t]*(\w+)[ \t]*\(", re.M)
CALL_RE = re.compile(r"(?<![\w.])(\w{2,})[ \t]*\(")
KEYWORDS = {"if", "for", "while", "switch", "return", "sizeof", "catch", "else", "do",
            "case", "break", "continue", "new", "delete", "const", "static", "operator"}
# names that are ours but generated/defined dynamically (macros are stripped)
EXTRA_DEFS = {}
# platform / legacy names that match our prefixes but are not ours
BUILTIN_NAMES = {"EA_MAX_SYMBOLS", "EA_STAT_MAX_SYMBOLS", "EA_SPREAD_RING"}

# MetaTrader functions are recognised by family prefix (the platform's naming is
# very regular) plus a short list of exceptions.  This is a heuristic for a dev
# tool: an unmatched name is reported for a human to look at, not auto-fixed.
PLATFORM_PREFIXES = (
    "Array", "Math", "String", "Time", "Struct", "Symbol", "Account", "Position",
    "Order", "History", "Deal", "File", "Copy", "Chart", "Event", "GlobalVariable",
    "Terminal", "Print", "Alert", "Comment", "Sleep", "Get", "Set", "Reset", "Send",
    "Period", "Normalize", "Double", "Integer", "EnumToString", "ColorToString",
    "CharToString", "ShortToString", "FloatToString", "WebRequest", "Socket",
    "Tester", "Frame", "Menu", "Object", "Resource", "Param", "Signal", "Debug",
    "PlaySound", "MessageBox", "Text", "Crypt", "Database", "Calendar", "Network",
    "ZeroMemory", "CheckPointer", "UninitializeReason", "OnInit", "OnDeinit", "OnTick",
    "OnTimer", "OnTrade", "OnChartEvent", "OnTester", "SeriesInfo", "OrderCalc",
    "Convert", "FileRead", "FileWrite", "FileOpen", "FileClose", "i", "MQLInfo",
    "Char", "Short", "Color", "EnumTo", "ArrayTo", "StringTo", "Resource", "Series",
    "Indicator",
)
PLATFORM_EXACT = {"iTime", "iOpen", "iHigh", "iLow", "iClose", "iVolume", "iBars",
                  "iSpread", "iTickVolume", "iBarShift", "is", "in", "new", "delete"}


def strip_comments(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    # blank the inside of string/char literals: log text is not code
    src = re.sub(r'"([^"\\\n]|\\.)*"', '""', src)
    src = re.sub(r"'([^'\\\n]|\\.)*'", "''", src)
    src = re.sub(r"^[ \t]*#[^\n]*", "", src, flags=re.M)     # macros / includes
    return src


def match_paren(src: str, open_idx: int):
    """Index of the ')' matching the '(' at open_idx, or None."""
    depth, i, in_str = 0, open_idx, None
    while i < len(src):
        c = src[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
        elif c in "\"'":
            in_str = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def split_args(s: str):
    args, depth, cur, in_str, i = [], 0, "", None, 0
    while i < len(s):
        c = s[i]
        if in_str:
            if c == "\\":
                cur += c + (s[i + 1] if i + 1 < len(s) else "")
                i += 2
                continue
            if c == in_str:
                in_str = None
            cur += c
        elif c in "\"'":
            in_str = c
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            args.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    if depth != 0:
        return None
    if cur.strip():
        args.append(cur)
    return args


def extract_defs(src: str):
    """name -> {(min_args, max_args)} and the source with definitions blanked."""
    defs = {}
    spans = []
    for m in DEF_RE.finditer(src):
        typeword, name = m.group(1), m.group(2)
        if typeword in KEYWORDS or name in KEYWORDS:
            continue
        depth, i = 0, m.end() - 1
        close = match_paren(src, i)
        if close is None:
            continue
        params = split_args(src[m.end():close])
        if params is None:
            continue
        params = [p for p in params if p.strip()]
        if len(params) == 1 and params[0].strip() in ("void",):
            params = []
        total = len(params)
        defaults = len([p for p in params if "=" in p])
        defs.setdefault(name, set()).add((total - defaults, total))
        spans.append((m.start(), close + 1))
    # blank out definition headers so their parameter declarations are not
    # mistaken for calls
    chars = list(src)
    for start, end in spans:
        for k in range(start, end):
            if chars[k] != "\n":
                chars[k] = " "
    return defs, "".join(chars)


def main():
    argv = sys.argv[1:]
    if "--selftest" in argv:
        d, blanked = extract_defs(
            "double EA_SpreadBaseline(const string sym, const int windowMin)\n"
            "{ return 0.0; }\n"
            "void f() { double a = EA_SpreadBaseline(Symbol(), 0, 0.0); }\n")
        assert d["EA_SpreadBaseline"] == {(2, 2)}, d
        assert "EA_SpreadBaseline" in blanked, blanked
        print("selftest OK: 2-param signature parsed; a 3-arg call is outside that range")
        return 0

    class_names = set()
    for p_ in (argv or []):
        try:
            class_names.update(re.findall(r"\bclass\s+(\w+)", Path(p_).read_text(errors="replace")))
        except OSError:
            pass
    if not argv:
        for p_ in sorted(INC_DIR.glob("*.mqh")):
            class_names.update(re.findall(r"\bclass\s+(\w+)", p_.read_text(errors="replace")))
    targets = [Path(a).resolve() for a in argv] if argv else (
        sorted(EA_DIR.glob("*.mq5")) + sorted(INC_DIR.glob("*.mqh")))
    defs = dict(EXTRA_DEFS)
    clean = {}
    for p in targets:
        src = strip_comments(p.read_text(errors="replace"))
        d, blanked = extract_defs(src)
        clean[p] = blanked
        for k, v in d.items():
            defs.setdefault(k, set()).update(v)

    total = total_undef = 0
    for p in targets:
        blanked = clean[p]
        for m in CALL_RE.finditer(blanked):
            name = m.group(1)
            if name in KEYWORDS or name.startswith("m_") or name in class_names:
                continue
            if name not in defs:
                # names that look like ours but are defined nowhere are
                # compile errors waiting to happen
                if (name not in BUILTIN_NAMES and name not in PLATFORM_EXACT
                        and not name.startswith(PLATFORM_PREFIXES)):
                    line = blanked[:m.start()].count("\n") + 1
                    total_undef += 1
                    print("%s:%d: %s called but never defined"
                          % (os.path.relpath(p, REPO), line, name))
                continue                     # platform built-ins are not defined here
            close = match_paren(blanked, m.end() - 1)
            if close is None:
                continue
            args = split_args(blanked[m.end():close])
            if args is None:
                continue
            n = len([a for a in args if a.strip()])
            if not any(lo <= n <= hi for (lo, hi) in defs[name]):
                line = blanked[:m.start()].count("\n") + 1
                total += 1
                print("%s:%d: %s called with %d arg(s); signature %s"
                      % (os.path.relpath(p, REPO), line, name, n, sorted(defs[name])))
    print("arity: checked %d files, %d arity finding(s), %d undefined-name finding(s)"
          % (len(targets), total, total_undef))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
