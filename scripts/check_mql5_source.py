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

    problems += check_duplicate_members(path, src)
    problems += check_identifiers(path, src)
    problems += check_members(path, src)
    problems += check_duplicate_declarations(path, src)
    problems += check_undeclared_variables(path, raw, src)

    #--- every call to our own helper namespace must exist somewhere
    if is_ea:
        for m in re.finditer(r"\b(EA_[A-Za-z_]\w*|Sig[A-Z]\w*)\s*\(", src):
            name = m.group(1)
            if name not in defined:
                line = src[:m.start()].count("\n") + 1
                problems.append(f"call to undefined helper {name}() at line {line}")
    return problems



#--- identifier rules -----------------------------------------------------------
# Two classes of compile error the call-based checks above cannot see, both found
# by READING the 65 EAs (neither the arity checker nor this one looked at plain
# identifiers):
#   * a reserved word used as a variable name (`bool long = ...` - `long`/`short`
#     are data types in MQL5 and cannot be redefined), and
#   * a project identifier that is never declared (`EA_MAX_SYM` for the real
#     constant `EA_MAX_SYMBOLS`).
# Both stop the whole 65-engine portfolio build from compiling.
RESERVED_TYPES = {"bool", "char", "uchar", "short", "ushort", "int", "uint", "long", "ulong",
                  "float", "double", "string", "datetime", "color", "void"}
RESERVED_OTHER = {"class", "struct", "enum", "union", "const", "private", "protected", "public",
                  "virtual", "delete", "override", "extern", "input", "static", "break",
                  "dynamic_cast", "operator", "case", "else", "continue", "for", "return",
                  "default", "if", "sizeof", "new", "switch", "do", "while", "this", "true",
                  "false", "template", "typename", "namespace"}
RESERVED = RESERVED_TYPES | RESERVED_OTHER
_TYPE_LEFT = (r"(?:const\s+)?(?:" + "|".join(sorted(RESERVED_TYPES - {"void"})) +
              r"|ENUM_\w+|S[A-Z]\w*|C[A-Z]\w*)")
RESERVED_DECL_RE = re.compile(
    r"(?<![\w.])" + _TYPE_LEFT + r"\s*[&*]?\s+(" + "|".join(sorted(RESERVED)) + r")\s*(?=[=;,\[)])")
RESERVED_VALUE_RE = re.compile(
    r"(?:!|&&|\|\||\?|=|\breturn)\s*(" + "|".join(sorted(RESERVED_TYPES - {"void"})) +
    r")\s*(?=[?:]|&&|\|\||==|!=|;|\)|,)")

PROJECT_ID_RE = re.compile(r"(?<![\w.:>])(EA_[A-Z][A-Z0-9_]*|Inp[A-Z]\w*|g_ea[A-Za-z0-9_]*|m_[A-Za-z]\w*)\b(?!\s*\()")
_DECL_NAME_RE = re.compile(
    r"(?<![\w.])(?!(?:return|else|case|new|delete|sizeof|goto|typename|operator|public|private|protected)\b)"
    r"[A-Za-z_]\w*(?:\s*<[^>;{}]*>)?(?:\s+[&*]?\s*|\s*[&*]\s*)([A-Za-z_]\w*)\s*(?=[=;,(\[):])")
_DEFINE_RE = re.compile(r"^[ \t]*#define[ \t]+([A-Za-z_]\w*)", re.M)
_ENUM_RE = re.compile(r"enum\s+[A-Za-z_]\w*\s*\{([^}]*)\}", re.S)
_declared_cache: dict[str, set[str]] = {}


def declared_names(paths: list[Path]) -> set[str]:
    """Every name the given sources declare (macro, enum constant, variable,
    member, parameter, function).  Deliberately generous: it exists to catch
    names that are declared NOWHERE, not to prove scoping."""
    key = "|".join(sorted(str(p) for p in paths))
    if key in _declared_cache:
        return _declared_cache[key]
    names: set[str] = set()
    for p in paths:
        try:
            raw = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        names.update(_DEFINE_RE.findall(raw))
        src = strip_noise(raw)
        names.update(m.group(1) for m in _DECL_NAME_RE.finditer(src))
        for m in _ENUM_RE.finditer(src):
            for v in m.group(1).split(","):
                nm = v.split("=")[0].strip()
                if nm:
                    names.add(nm)
        # `for(int i = 0, j = 1; ...)` / `double a = 1, b = 2;` second declarators
        for m in re.finditer(r",\s*([A-Za-z_]\w*)\s*(?==)", src):
            names.add(m.group(1))
    _declared_cache[key] = names
    return names


def _unit_for(path: Path) -> list[Path]:
    unit = sorted(INCLUDES.glob("*.mqh")) + [path]
    build = ROOT / "portfolio-EA" / "build"
    if build in path.parents:
        unit += [build / "PortfolioStrategies.mqh", build / "AllEnginesEA.mq5"]
    return unit


def check_identifiers(path: Path, src: str) -> list[str]:
    problems = []
    for m in RESERVED_DECL_RE.finditer(src):
        line = src[:m.start()].count("\n") + 1
        problems.append(f"reserved word '{m.group(1)}' used as a variable name at line {line} "
                        f"(MQL5 reserved words cannot name identifiers - compile error)")
    for m in RESERVED_VALUE_RE.finditer(src):
        line = src[:m.start()].count("\n") + 1
        problems.append(f"reserved word '{m.group(1)}' used as a value at line {line} "
                        f"(did a variable get named after a data type?)")
    declared = declared_names(_unit_for(path))
    seen: set[str] = set()
    for m in PROJECT_ID_RE.finditer(src):
        name = m.group(1)
        if name in declared or name in seen:
            continue
        seen.add(name)
        line = src[:m.start()].count("\n") + 1
        problems.append(f"undeclared identifier {name} at line {line} (not defined in this file "
                        f"or the shared headers - compile error)")
    return problems


#--- duplicate-member rule ------------------------------------------------------
# A class that defines the same method twice - e.g. a patched-in event handler landing
# next to one that already existed - is a hard compile error in MQL5, and none of the
# rules above inspects class bodies.  Overloads are legal, so the comparison is on the
# normalised SIGNATURE (name + parameter TYPES), never on the name alone.
_MEMBER_SIG_RE = re.compile(
    r"(?m)^\s*(?:virtual\s+|static\s+)?(?:[A-Za-z_][\w:<>*&]*\s+)+"
    r"([A-Za-z_]\w*)\s*\(([^;{)]*)\)\s*(?:const|override)?\s*\{")


def _normalise_params(raw: str) -> str:
    """Parameter types with names removed, so a redeclaration with renamed parameters matches."""
    parts = []
    for chunk in raw.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        tokens = chunk.replace("*", " * ").replace("&", " & ").split()
        if len(tokens) >= 2 and re.fullmatch(r"[A-Za-z_]\w*(\[\])?", tokens[-1]):
            tokens = tokens[:-1]                     # drop the parameter name
        parts.append(" ".join(tokens))
    return ", ".join(parts)


def check_duplicate_members(path: Path, src: str) -> list[str]:
    problems = []
    for class_match in re.finditer(r"\b(?:class|struct)\s+([A-Za-z_]\w*)[^;{]*\{", src):
        name = class_match.group(1)
        i, depth, j = class_match.end(), 1, class_match.end()
        while j < len(src) and depth:
            depth += (src[j] == "{") - (src[j] == "}")
            j += 1
        body = src[i:j - 1]
        seen: dict[tuple[str, str], int] = {}
        for m in _MEMBER_SIG_RE.finditer(body):
            if m.group(1) in RESERVED:
                continue          # `else if(...) {` / `while(...) {` are control flow, not members
            params = _normalise_params(m.group(2))
            sig = (m.group(1), params)
            line = src[:i].count("\n") + 1 + body[:m.start()].count("\n")
            if sig in seen:
                problems.append(f"duplicate member '{m.group(1)}({params})' in {name} at line {line} "
                                f"(already defined at line {seen[sig]}) - compile error")
            else:
                seen[sig] = line
    return problems


#--- struct member rule ---------------------------------------------------------
# `ep.emaPeriod = 20;` on a struct that has no such member is a compile error.
# 13 EAs did exactly that for SEmaPullbackParams (and one read a SEAContext field
# that was never declared): the arity / call checks never look at `var.member`.
# Variable types come from the enclosing function's parameters and locals first
# (so two functions may reuse the name `p` for different types), then from any
# file-scope declaration.
_STRUCT_FIELDS: dict[str, set[str]] = {}
_FUNC_RE = re.compile(r"([A-Za-z_]\w*)\s*\(([^()]*)\)\s*(?:const\s*)?(?:override\s*)?\{")


def struct_fields() -> dict[str, set[str]]:
    if _STRUCT_FIELDS:
        return _STRUCT_FIELDS
    text = "\n".join(strip_noise(p.read_text(encoding="utf-8", errors="replace"))
                     for p in sorted(INCLUDES.glob("*.mqh")))
    for m in re.finditer(r"\bstruct\s+([A-Za-z_]\w*)\s*\{", text):
        i, depth, j = m.end(), 1, m.end()
        while j < len(text) and depth:
            depth += (text[j] == "{") - (text[j] == "}")
            j += 1
        body = text[i:j - 1]
        fields: set[str] = set(re.findall(r"\b([A-Za-z_]\w*)\s*\(", body))      # methods
        for d in re.finditer(r"^\s*(?:const\s+)?[A-Za-z_][\w:<>]*\s*[&*]?\s+([^;(){}]+);", body, re.M):
            for part in d.group(1).split(","):
                nm = re.match(r"\s*[&*]?\s*([A-Za-z_]\w*)", part)
                if nm:
                    fields.add(nm.group(1))
        _STRUCT_FIELDS[m.group(1)] = fields
    return _STRUCT_FIELDS


def _typed_vars(text: str, structs: dict[str, set[str]]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for st in structs:
        for m in re.finditer(r"(?<![\w.])" + st + r"\b\s*[&*]?\s*([A-Za-z_]\w*)\b(?=\s*[\[;=,)(])", text):
            out.setdefault(m.group(1), set()).add(st)
    return out


def check_members(path: Path, src: str) -> list[str]:
    structs = struct_fields()
    if not structs:
        return []
    file_vars = _typed_vars(src, structs)
    problems: list[str] = []
    seen: set[tuple[str, str, int]] = set()

    def scan(body: str, offset_line: int, scope_vars: dict[str, set[str]], local_names: set[str]) -> None:
        for var in set(scope_vars) | set(file_vars):
            if var not in scope_vars and var in local_names:
                continue          # declared locally with a non-struct type (e.g. MqlRates d[])
            types = scope_vars.get(var) or file_vars.get(var, set())
            allowed = set().union(*(structs[t] for t in types)) if types else set()
            for m in re.finditer(r"(?<![\w.])" + re.escape(var) + r"(?:\s*\[[^\]]*\])?\s*\.\s*([A-Za-z_]\w*)", body):
                if m.group(1) in allowed:
                    continue
                line = offset_line + body[:m.start()].count("\n")
                key = (var, m.group(1), line)
                if key in seen:
                    continue
                seen.add(key)
                problems.append(f"struct member '{var}.{m.group(1)}' at line {line}: "
                                f"{'/'.join(sorted(types))} has no such member (compile error)")

    covered: list[tuple[int, int]] = []
    for fm in _FUNC_RE.finditer(src):
        if fm.group(1) in ("if", "for", "while", "switch", "catch"):
            continue
        i, depth, j = fm.end(), 1, fm.end()
        while j < len(src) and depth:
            depth += (src[j] == "{") - (src[j] == "}")
            j += 1
        body = src[i:j - 1]
        scope_text = fm.group(2) + ";\n" + body
        scope_vars = _typed_vars(scope_text, structs)
        local_names = set(re.findall(
            r"(?<![\w.])[A-Za-z_]\w*(?:\s+[&*]?\s*|\s*[&*]\s*)([A-Za-z_]\w*)\b(?=\s*[\[;=,)(])", scope_text))
        scan(body, src[:i].count("\n") + 1, scope_vars, local_names)
        covered.append((i, j))
    return problems


#--- scope rules ----------------------------------------------------------------
# Two more classes the call-based checks cannot see.  Both are plain compile
# errors in MQL5 and both are cheap to rule out statically:
#   * the same name declared twice in one block (copy-paste duplicates), and
#   * a variable that is used but never declared in the function, its class, the
#     file or the shared headers (a typo - `sweepIndx` for `sweepIdx`).
_DECL_TYPES = (r"(?:bool|char|uchar|short|ushort|int|uint|long|ulong|float|double|string|datetime|color|"
               r"Mql\w+|ENUM_\w+|S[A-Z]\w*|C[A-Z]\w*)")
_DUP_RE = re.compile(r"[{}]|(?:(?<=[;{}])|^)\s*(?:static\s+|const\s+)*(" + _DECL_TYPES +
                     r")(?:\s+[&*]?\s*|\s*[&*]\s*)([A-Za-z_]\w*)\s*(?=[=;,\[(])")
_KEYWORDS = RESERVED | {"NULL", "ref"}
_BUILTIN_VARS = {"_Symbol", "_Point", "_Digits", "_Period", "_LastError", "_StopFlag",
                 "_UninitReason", "_RandomSeed"}
_FUNC_SKIP = ("if", "for", "while", "switch", "catch")


def _function_spans(src: str):
    for fm in _FUNC_RE.finditer(src):
        if fm.group(1) in _FUNC_SKIP:
            continue
        i, depth, j = fm.end(), 1, fm.end()
        while j < len(src) and depth:
            depth += (src[j] == "{") - (src[j] == "}")
            j += 1
        yield fm, i, j


def check_duplicate_declarations(path: Path, src: str) -> list[str]:
    problems = []
    for fm, i, j in _function_spans(src):
        body = src[i:j - 1]
        params = set(re.findall(r"(?:" + _DECL_TYPES + r")(?:\s+[&*]?\s*|\s*[&*]\s*)([A-Za-z_]\w*)", fm.group(2)))
        stack = [params]
        for t in _DUP_RE.finditer(body):
            tok = t.group(0).strip()
            if tok == "{":
                stack.append(set())
            elif tok == "}":
                if len(stack) > 1:
                    stack.pop()
            elif t.group(2) in stack[-1]:
                line = src[:i].count("\n") + 1 + body[:t.start()].count("\n")
                problems.append(f"'{t.group(2)}' is declared twice in the same block at line {line} "
                                f"(in {fm.group(1)}) - compile error")
            else:
                stack[-1].add(t.group(2))
    return problems


def _blank_function_bodies(src: str) -> str:
    out = list(src)
    for fm, i, j in _function_spans(src):
        for k in range(i, j - 1):
            if out[k] != "\n":
                out[k] = " "
    return "".join(out)


def _outer_declared(raw: str, src: str) -> set[str]:
    """Names visible outside any function body: class members, globals, macros,
    enum constants, struct fields.  Parameter lists are removed first - a
    parameter name is not a global."""
    outer = _blank_function_bodies(src)
    for _ in range(3):
        outer = re.sub(r"\([^()]*\)", "()", outer)
    names = {m.group(1) for m in _DECL_NAME_RE.finditer(outer)}
    names.update(_DEFINE_RE.findall(raw))
    for m in _ENUM_RE.finditer(src):
        for v in m.group(1).split(","):
            nm = v.split("=")[0].strip()
            if nm:
                names.add(nm)
    names.update(re.findall(r",\s*([A-Za-z_]\w*)\s*(?=[=;,\[])", outer))
    return names


def _header_names() -> set[str]:
    key = "__headers__"
    if key not in _declared_cache:
        names: set[str] = set()
        for p in sorted(INCLUDES.glob("*.mqh")):
            raw = p.read_text(encoding="utf-8", errors="replace")
            names |= _outer_declared(raw, strip_noise(raw))
        _declared_cache[key] = names
    return _declared_cache[key]


def check_undeclared_variables(path: Path, raw: str, src: str) -> list[str]:
    problems: list[str] = []
    visible_outer = _header_names() | _outer_declared(raw, src)
    build = ROOT / "portfolio-EA" / "build"
    if build in path.parents:                      # the host and its strategies share one program
        for other in (build / "PortfolioStrategies.mqh", build / "AllEnginesEA.mq5"):
            if other != path and other.exists():
                o_raw = other.read_text(encoding="utf-8", errors="replace")
                visible_outer |= _outer_declared(o_raw, strip_noise(o_raw))
    reported: set[tuple[str, str]] = set()
    for fm, i, j in _function_spans(src):
        body = src[i:j - 1]
        scope = fm.group(2) + ";\n" + body
        local = {m.group(1) for m in _DECL_NAME_RE.finditer(scope)}
        local.update(re.findall(r",\s*([A-Za-z_]\w*)\s*(?=[=;,\[)])", scope))
        visible = local | visible_outer
        for m in re.finditer(r"(?<![\w.:>#])([a-z_][A-Za-z0-9_]*)\b(?!\s*\()", body):
            nm = m.group(1)
            if nm in _KEYWORDS or nm in _BUILTIN_VARS or nm in visible or re.match(r"clr[A-Z]", nm):
                continue          # (clr* = MQL5's built-in web colours)
            if (fm.group(1), nm) in reported:
                continue
            reported.add((fm.group(1), nm))
            line = src[:i].count("\n") + 1 + body[:m.start()].count("\n")
            problems.append(f"'{nm}' is used but never declared (in {fm.group(1)}, line {line}) - compile error")
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
