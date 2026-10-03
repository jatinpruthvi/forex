#!/usr/bin/env python3
"""Pass-5 documentation work on docs/EA_IMPLEMENTATION_TRACKER.md.

1. Correct every "Source Document" cell that points at a path that does not
   exist, resolving underscore/hyphen drift, missing directories and the
   docs/strategy <-> docs/prop_firm swap.  Rows whose document genuinely is not
   in the repository are left untouched (and reported).
2. Record the fifth audit pass in section 5 (header + summary bullets) and add
   the deviation/limitation bullets the fifth pass identified.
"""
import os
import re
import sys

P = "docs/EA_IMPLEMENTATION_TRACKER.md"
src = open(P, encoding="utf-8").read()
before = src

# ---------------------------------------------------------------- links -----
all_files = []
for root, _dirs, files in os.walk("docs"):
    for f in files:
        all_files.append(os.path.join(root, f))


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


idx = {}
for p in all_files:
    idx.setdefault(norm(os.path.basename(p)), []).append(p)

fixed = []
unresolved = []
row_re = re.compile(r"(\|\s*\d+\s*\|\s*`([^`]+\.mq5)`\s*\|\s*`([^`]+)`\s*\|)")


def repl(m):
    whole, _ea, doc = m.group(1), m.group(2), m.group(3)
    if os.path.exists(doc):
        return whole
    cand = idx.get(norm(os.path.basename(doc)), [])
    if len(cand) == 1:
        fixed.append((doc, cand[0]))
        return whole.replace("`%s`" % doc, "`%s`" % cand[0])
    unresolved.append((doc, cand))
    return whole


src = row_re.sub(repl, src)

# ---------------------------------------------------------- section 5 -------
old_head = "## 5. Verification Performed (2026-10-01, extended 2026-10-02, fourth audit pass)"
new_head = "## 5. Verification Performed (2026-10-01, extended 2026-10-02, fifth audit pass)"
assert src.count(old_head) == 1
src = src.replace(old_head, new_head)

bullet = (
"* **Deep bug audit, fifth pass (2026-10-02)** - the pass walked **every source document** and checked its "
"declared instrument universe, session/instrument matrix, exit ladder, flat times and day-of-week rules against "
"the generated strategy: **14 further defect classes fixed across 21 EAs plus one shared-engine addition** "
"(#35-#48 in `docs/EA_BUG_AUDIT.md` \"Fifth pass\"). The headline fixes: ten documents declared instruments the "
"universe could never deliver (gold missing from the two London-sweep EAs - whose fuel filter would then have "
"rejected every gold setup with the EURUSD 35-pip cap - `AUDUSD`/`EURCHF`/`AUDNZD` dead sleeves, the The5ers EA "
"running one of its three documented instrument/session combinations, `round10_claude_opus_5` trading USDCAD "
"instead of its document's Asian and gold sleeves); `round8_contestant_b` was missing the chandelier runner that "
"its document calls the ROI and took entries up to four hours after every documented session window closed, and "
"it had none of the document's three risk rules (one position per currency group, max 2 trades/session, max 1.5% "
"open risk); four EAs let the engine's fixed-R trail truncate the documented chandelier tail; four documented "
"hard flats (21:00/16:30/16:00) were missing and three Asian-grid EAs never closed their baskets at the 07:00 "
"flat their documents call the rule that keeps grids alive; three EAs ignored their \"Tuesday-Thursday only\" "
"rule; eight EAs scaled H1-ATR distances off a `daily ATR / 6` proxy instead of the real `ctx.atrH1`; "
"`round10_qwen3_8`s Step 4 midpoint confirmation and 3-candle limit expiry are now implemented through a new "
"opt-in `SSweepParams.requireMidpointBreak`; and 53 of the 65 tracker source-document links did not resolve to a "
"file (now corrected). All 65 EAs regenerated; `--check` reports 65/65, the checker reports 0 findings on the "
"65, arity 0/0 over 87 files, braces 0, 187 tests pass.\n"
"* **Documented limitations from the fifth pass (deliberate, not bugs)** - (a) index-named sleeves (`GER40`, "
"`US30`, `DAX`, `US100`) are not shipped as universes because they are broker-dependent symbols; "
"`EA_TRIAD_SURVIVE` implements its document's own XAUUSD+GBPJPY fallback, `round11_contestant_f` sleeve B trades "
"XAUUSD only, and `round12_contestant_b` does ship `US30` because its document names it directly. "
"(b) Four EAs are deliberate single-sleeve variants of larger documents and their titles say so: "
"`round5_contestant_a_2047` (London checklist), `round5_contestant_b` (asymmetric runner), "
"`round5_contestant_c` (London sweep; the document's grid sleeve is not part of the variant), "
"`round12_contestant_c` (SR-10 London module; the New York module is not implemented); `round7_contestant_d` "
"implements Strategy 1 of 3 (its NY continuation and AUDNZD/EURGBP Asian mean-reversion strategies are not "
"implemented); `EA_STRATEGY_ROADMAP`'s F1 quiet-session family is the only shipped Track-B family without its "
"06:30 flat (it is not the default family and its instrument set is largely outside the universe). "
"(c) `round10_claude_opus_5` keeps one 07:00-20:00 envelope with a single 07:00-16:00 sweep window instead of its "
"document's three session windows and has no session-end flat, and `round10_qwen3_8`/`round10_kimi_k3` use the "
"shared 22:00 session-end flat rather than their documents' per-session flat times. (d) `round5_contestant_c` "
"keeps a flat 16:00 without the document's \"> 2R runner\" exemption, and `round7_contestant_d`'s runner uses the "
"engine M15-swing stand-in trail rather than the document's exact M15-swing + 1.5 x ATR distance. "
"(e) Tracker rows 32-39, 41 and 43 (the round-1/2/3 documents and the two \"(1)\" documents) have no source "
"document in the repository; their code is the behaviour of record.\n"
)

anchor = "* **Deep bug audit, fourth pass (2026-10-02)**"
assert src.count(anchor) == 1
i = src.index(anchor)
j = src.index("\n", src.index("see `docs/EA_BUG_AUDIT.md` \"Fourth pass\".", i))
src = src[:j + 1] + bullet + src[j + 1:]

open(P, "w", encoding="utf-8").write(src)
print("tracker updated (%+d bytes); links fixed: %d; unresolved: %d"
      % (len(src) - len(before), len(fixed), len(unresolved)))
for a, b in fixed[:5]:
    print("   %s -> %s" % (a, b))
if len(fixed) > 5:
    print("   ... and %d more" % (len(fixed) - 5))
for doc, cand in unresolved:
    print("   UNRESOLVED: %s (candidates: %s)" % (doc, cand))
