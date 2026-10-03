#!/usr/bin/env python3
"""One-off: make AllEnginesEA.mq5 carry all 65 strategies inside itself.

Owner: portfolio-EA.  Reason (user, 2026-10-03): "this is mql5 I do not want
python program for that we can build ea" - the deliverable must be ONE EA file,
not a host that needs a sibling include.  After this patch the generated EA has
exactly one #include left (the shared engine header every delivered EA already
uses); the 65 strategies are inlined verbatim.

Run once, then: python3 portfolio-EA/gen_portfolio_ea.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GEN = ROOT / "portfolio-EA" / "gen_portfolio_ea.py"
VER = ROOT / "portfolio-EA" / "verify_portfolio.py"

src = GEN.read_text(encoding="utf-8")

# --- 1. constants next to INC_MARKER ------------------------------------------
old = "INC_MARKER = '#include \"..\\\\..\\\\Include\\\\EACommon.mqh\"'"
assert src.count(old) == 1, "INC_MARKER anchor"
new = (
    old + "\n"
    "STRAT_FILE   = \"PortfolioStrategies.mqh\"\n"
    "STRAT_MARKER = '#include \"PortfolioStrategies.mqh\"'\n"
    "INLINE_BEGIN = \"//=== BEGIN inlined \" + STRAT_FILE\n"
    "INLINE_END   = \"//=== END inlined \" + STRAT_FILE"
)
src = src.replace(old, new)

# --- 2. host header: say what the file is ------------------------------------
old = ("//| Requires MQL5_Master/Include/*.mqh in <data>\\MQL5\\Include\\ and this  |\n"
       "//| folder in <data>\\MQL5\\Experts\\portfolio\\.                           |")
assert src.count(old) == 1, "host header anchor"
new = ("//| ONE FILE = THE WHOLE EA: all @@COUNT@@ strategies are inlined          |\n"
       "//| below, so nothing from portfolio-EA/ has to ship next to it.  It     |\n"
       "//| uses the same shared engine header as the 65 delivered EAs:          |\n"
       "//|   <data>\\MQL5\\Include\\EACommon.mqh  (MQL5_Master/Include/*.mqh)     |\n"
       "//| Copy this one file to <data>\\MQL5\\Experts\\ and compile it.           |")
src = src.replace(old, new)

# --- 3. inline helper, right before render() ---------------------------------
old = "def render(engine_values: set[str], specs) -> tuple[str, str, list[dict]]:"
assert src.count(old) == 1, "render anchor"
new = (
    "def inline_strategies(host: str, strategies: str) -> str:\n"
    "    \"\"\"Fold the 65 strategy classes INTO the EA so it is one file to\n"
    "    compile.  The block is byte-identical to the separately emitted\n"
    "    PortfolioStrategies.mqh, which stays as the review copy.\"\"\"\n"
    "    assert host.count(STRAT_MARKER) == 1, \"strategy include marker not found\"\n"
    "    block = (INLINE_BEGIN + \" - the 65 strategies live inside this EA - \"\n"
    "             \"do not edit here, see README\\n\"\n"
    "             + strategies + INLINE_END + \" ===\\n\")\n"
    "    return host.replace(STRAT_MARKER, block)\n\n\n"
    + old
)
src = src.replace(old, new)

# --- 4. call it after the template is filled ---------------------------------
old = ('            .replace("@@REGISTRY@@", "\\n".join(registry)))\n'
       "    return strategies, host, manifest")
assert src.count(old) == 1, "render return anchor"
new = ('            .replace("@@REGISTRY@@", "\\n".join(registry)))\n'
       "    host = inline_strategies(host, strategies)\n"
       "    return strategies, host, manifest")
src = src.replace(old, new)

# --- 5. summary print ---------------------------------------------------------
old = '    print(f"     host       : AllEnginesEA.mq5 (registry, snapshot/restore, scheduler, tags)")'
assert src.count(old) == 1, "summary anchor"
new = ('    print("     EA         : build/AllEnginesEA.mq5 - ONE file to compile; the 65")\n'
       '    print("                  strategies are inlined, only the shared engine header")\n'
       '    print("                  (..\\\\..\\\\Include\\\\EACommon.mqh) is still needed")')
src = src.replace(old, new)

GEN.write_text(src, encoding="utf-8")
print("generator patched: strategies are inlined into AllEnginesEA.mq5")

# --- 6. verifier: prove the EA is one self-contained file ---------------------
ver = VER.read_text(encoding="utf-8")
old = "    # 10 - tracker EA (PortfolioEA.mq5 in src/): read-only, by magic ------------------"
assert ver.count(old) == 1, "verifier block-10 anchor"
new = (
    "    # 11 - the EA is ONE file: the strategies are inside it, not a sibling include --\n"
    "    check('#include \"PortfolioStrategies.mqh\"' not in host,\n"
    "          \"AllEnginesEA.mq5 still #includes the strategies file\")\n"
    "    check(strategies in host, \"the strategy text is not inlined verbatim into the EA\")\n"
    "    bslash = chr(92)\n"
    "    check(host.count(\"//=== BEGIN inlined PortfolioStrategies.mqh\") == 1 and\n"
    "          host.count(\"//=== END inlined PortfolioStrategies.mqh\") == 1,\n"
    "          \"inlined strategy block markers missing\")\n"
    "    quoted = re.findall(r'^\\s*#include\\s+\"([^\"]+)\"', host, re.M)\n"
    "    check(quoted == [\"..\" + bslash * 2 + \"Include\" + bslash + \"EACommon.mqh\"],\n"
    "          f\"the EA must need only the shared engine header, found: {quoted}\")\n"
    "    check(len(re.findall(r\"class P\\d+_Port\\s*:\\s*public\\s\", host)) == 65,\n"
    "          \"the EA does not carry all 65 strategy wrappers\")\n"
    "    check(host.count(\"{ magic\" ) == 0 or True, \"\")  # placeholder removed below\n"
    "\n" + old
)
ver = ver.replace(old, new).replace('    check(host.count("{ magic" ) == 0 or True, "")  # placeholder removed below\n', "")
VER.write_text(ver, encoding="utf-8")
print("verifier patched: +1 self-contained-EA block")
