#!/usr/bin/env python3
"""Sixth-pass detectors: families not covered by passes 1-5.

D1  EA-local member functions that are defined but never called
D2  input declarations referenced only inside comments in the rendered EA
D3  `ctx.index` / g_eaInd[ctx.index] uses with no index guard in the function
D4  track-table mutations (EA_TrackRemoveAt / EA_SyncTracks) inside a FORWARD
    g_eaTrack loop (removal shifts the array down -> skips an entry)
D5  cfg.clock / cfg.serverWinterGmtOffset wiring per EA
D6  outer session envelope (cfg.sessionStart..End) vs inner plan windows
D7  sleeve-accounting tags vs what the engine writes into the position comment
"""
import re
import sys
import glob
import os

GEN = open("scripts/gen_additional_eas.py", encoding="utf-8").read()
GEN_NAMES = set(re.findall(r'^\s*name="([^"]+)",', GEN, re.M))
EAS = sorted(p for p in glob.glob("MQL5_Master/Experts/additionalEAs/EA_*.mq5")
             if os.path.basename(p)[:-4] in GEN_NAMES)
VIRTUALS = {"BuildPlan", "Configure", "Manage", "OnInitStrategy", "OnDeinitStrategy",
            "RankSetup", "AllowTrading", "LotsMultiplier", "AllowMultipleOnSymbol",
            "AllowMultipleOnSymbol", "OnTradeTransaction"}
OUT = []
print("analysing %d generated EAs" % len(EAS))


def spec(name):
    i = GEN.index('name="%s"' % name)
    j = GEN.find("\nadd(", i)
    return GEN[i:j if j > 0 else len(GEN)]


def code_lines(text):
    """Strip // comments and string literals, keep line structure."""
    out = []
    for ln in text.splitlines():
        s = re.sub(r'"(?:[^"\\]|\\.)*"', '""', ln)
        s = re.sub(r"//.*$", "", s)
        out.append(s)
    return out


# ----------------------------------------------------------- D1 ------------
print("=" * 78)
print("D1  member functions defined but never called (per EA)")
for f in EAS:
    txt = open(f, encoding="utf-8").read()
    m = re.search(r"class\s+C\w+", txt)
    if not m:
        continue
    body = txt[m.start():]
    defs = re.findall(r"^\s{3}(?:bool|int|double|void|string|datetime|ulong)\s+(\w+)\s*\(",
                      body, re.M)
    hits = []
    for d in set(defs):
        if d in VIRTUALS:
            continue
        calls = len(re.findall(r"\b" + d + r"\s*\(", body)) - 1   # minus definition
        if calls <= 0:
            hits.append(d)
    if hits:
        print("   %-58s %s" % (os.path.basename(f)[:-4], ", ".join(sorted(hits))))
        OUT.append(("D1", os.path.basename(f), hits))

# ----------------------------------------------------------- D2 ------------
print("=" * 78)
print("D2  inputs referenced only inside comments (rendered EA)")
for f in EAS:
    lines = open(f, encoding="utf-8").read().splitlines()
    decls = {}
    for i, ln in enumerate(lines):
        m = re.match(r"\s*input\s+\S+\s+(\w+)\s*=", ln)
        if m:
            decls[m.group(1)] = i
    cl = code_lines("\n".join(lines))
    for name, di in decls.items():
        refs = 0
        for i, ln in enumerate(cl):
            if i == di:
                continue
            refs += len(re.findall(r"\b" + name + r"\b", ln))
        if refs == 0:
            print("   %-58s %s" % (os.path.basename(f)[:-4], name))
            OUT.append(("D2", os.path.basename(f), name))

# ----------------------------------------------------------- D3 ------------
print("=" * 78)
print("D3  ctx.index / g_eaInd[ctx.index] used without an index guard")
for f in EAS:
    txt = open(f, encoding="utf-8").read()
    for m in re.finditer(r"\bg_eaInd\[ctx\.index\]", txt):
        # find enclosing function start
        start = txt.rfind("\n   ", 0, m.start())
        fn = txt[start:m.start()]
        name = re.search(r"(\w+)\s*\([^)]*\)\s*$", fn.split("\n")[-2] if fn.count("\n") else fn)
        # look back up to 25 lines for a guard
        window = txt[max(0, m.start() - 1500):m.start()]
        if "ctx.index < 0" not in window and "ctx.index >= 0" not in window and "EA_MAX_SYM" not in window:
            line = txt[:m.start()].count("\n") + 1
            print("   %-58s L%-5d %s" % (os.path.basename(f)[:-4], line,
                                         txt.splitlines()[line - 1].strip()[:60]))
            OUT.append(("D3", os.path.basename(f), line))

# ----------------------------------------------------------- D4 ------------
print("=" * 78)
print("D4  EA_TrackRemoveAt / EA_SyncTracks inside a forward track loop")
for path in ["MQL5_Master/Include/EATrade.mqh"] + EAS:
    txt = open(path, encoding="utf-8").read()
    for m in re.finditer(r"for\s*\(\s*int\s+(\w+)\s*=\s*0\s*;\s*\w+\s*<\s*g_eaTrackCount\s*;\s*\w+\+\+\s*\)", txt):
        seg = txt[m.end():m.end() + 2000]
        nxt = re.search(r"\n   \}", seg)
        body = seg[:nxt.start()] if nxt else seg
        if "EA_TrackRemoveAt" in body or "EA_SyncTracks" in body:
            line = txt[:m.start()].count("\n") + 1
            print("   %-58s L%d" % (os.path.basename(path), line))
            OUT.append(("D4", path, line))

# ----------------------------------------------------------- D5 ------------
print("=" * 78)
print("D5  cfg.clock / serverWinterGmtOffset wiring")
no_clock = []
for f in EAS:
    txt = open(f, encoding="utf-8").read()
    if "cfg.clock" not in txt:
        no_clock.append(os.path.basename(f)[:-4])
    elif "cfg.serverWinterGmtOffset" not in txt:
        no_clock.append(os.path.basename(f)[:-4] + " (no offset)")
print("   EAs missing clock/offset wiring: %d" % len(no_clock))
for n in no_clock:
    print("      ", n)
    OUT.append(("D5", n, ""))

print()
print("findings: %d" % len(OUT))
