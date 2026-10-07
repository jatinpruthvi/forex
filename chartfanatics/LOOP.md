# ChartFanatics EA loop — plan / build / judge

> Designed with the vendored skill **`.agents/skills/loop-design-check`** (judgment layer: decidable
> goal, five failure modes, human red lines), mechanism layer from
> **`.agents/skills/continuous-agent-loop`**. Lineage of the skill: Wiener's two-level feedback,
> Anatoli's *Loops explained*, Addy Osmani's *Loop Engineering*.
>
> **The loop is the worker, not the acceptance officer.** It stops at `awaiting_human`; a person
> flips `done` (`cf_loop.py signoff <card> --by NAME`).

40 of the 47 ChartFanatics cards still have no EA. Each one is the same job —
read the playbook → write the EA to the repository's house contract → prove it. That is exactly
the shape a loop fits, so the pipeline is written down here and implemented in
[`loop/cf_loop.py`](loop/cf_loop.py), with per-card state in `loop/state.json` and per-card
acceptance in `loop/specs/<slug>.json`.

## Step 0 — should this even be a loop? (gate, any miss = veto)

| Gate | This repo | Verdict |
|---|---|---|
| Repeats weekly or more | 40 cards, each a full read → spec → EA → verify cycle | ✅ |
| Verification can be automated | `scripts/check_mql5_source.py` (static contract), `tests/test_chartfanatics_sync.py` (doc rule → code table), manifest/magic checks, and the MT5 tester harness that writes one CSV row per EA | ✅ |
| Token budget can take it | bounded by the retry cap and one card at a time | ✅ |
| The agent has tools that run and see results | checker, test suite, git, the MT5 harness on the Windows box | ✅ |

**Baseline that makes it deserve a loop** (per the skill: a repo without one only amplifies errors):
the static checker, the sync test module, the family contract tests, `gen_todos.py` keeping the board
and cards in sync, and the tester harness producing `EA_TestReports/<strategy>_<magic>_<symbol>.csv`.

## Step 1 — the goal (machine-decidable)

**Done for one card** = all acceptance checks in that card's spec pass → the loop sets
`awaiting_human`; the human then flips `done`.

The checks (`cf_loop.py`, one function each, all deterministic):

| Check | Decides |
|---|---|
| `ea_exists` | the EA file named in the spec exists |
| `magic_ok` | magic inside 3201–3247, unique, and `InpMagicNumber` matches |
| `checker_clean` | `check_mql5_source.py` over the family: 0 findings |
| `sync_rules` | ≥ `rule_count` doc rules pinned in the rule → code table **and** every pattern still matches the source **and** the sync suite passes |
| `manifest_entry` | `manifest.json` agrees with the spec (EA + magic) |
| `card_tracking` | the card's Verdict / Instruments / Timeframe fields are filled — the strategy was understood *before* it was coded |
| `boundaries_intact` | acceptance spec, judge scripts and test list unchanged since plan (see below) |
| `windows_report` | MT5 tester row for the magic parses with `trades >= 0`, else reported as *PENDING (Windows stage owed)* |

**Boundaries** (the Goodhart antibody — a done-criterion alone is a licence to cheat):

1. the acceptance spec may not change after `plan` (only `replan`, which is logged and bumps the
   version; lowering the rule floor after judging is refused);
2. the judge may not change after `plan` — the build cannot loosen the thing that grades it. Frozen:
   the whole static checker, the sync test's **machinery** (everything but the rule table), and
   **every other card's rule table**. A build may add *its own* card's rule table (that is the
   deliverable) and nothing else; a rewritten rule that a finished card was judged against fails
   `boundaries_intact`;
3. no test file may be deleted or weakened;
4. `done` is flipped by a human only.

**Failure fallback:** any check fails → back to `planned` with the failure reason, attempt counter +1;
at 3 attempts the card goes to `escalated` and the loop stops touching it until a human runs `reset`.
A failure caused by *another* card's EA (a repo-wide gate) sets `blocked`, does **not** burn this
card's attempts, and names the culprit.

**Layered goal + reconciliation over assertion:** the checks above are assertions, so the Windows
tester report (an artifact the EA itself writes, not something the builder can phrase) is the
reconciliation anchor; while it is missing the card is `awaiting_human` **with the Windows stage
listed as owed**, never silently "verified".

## Step 2 — loop type

**Servo with an exit.** Every card has a decidable "done" test, so the loop stops on reaching it per
card, and stops entirely when the queue drains (or a card escalates). No regulator/timer behaviour is
wanted: nothing here needs to be maintained on a schedule, and a poll would just burn tokens.

## Step 3 — skeleton

**Document-driven dispatch + plan / build / judge.** The **work card is the task queue and the state
machine**: the human writes the problem side (stages, Tracking verdict), the loop writes the result
side (spec, judge verdict, status), and state only ever advances one way — until a human resets it.

| Role | Who | Enforced by |
|---|---|---|
| **Plan** | agent + human | `cf_loop.py plan` refuses a card with no source doc; the spec's `rule_count` is a floor the planner sets from the document |
| **Build** | the agent (writes the `.mq5`, wires the card, extends the rule table) | `cf_loop.py build` prints the dispatch + the boundaries; the builder never edits the spec |
| **Judge** | `cf_loop.py judge` — deterministic scripts, **not** the builder | runs the checker, the sync table + suite, the manifest/card checks, and the hash boundaries; independent because the builder cannot edit it (boundary 2) |

Three iron rules from the skill, mapped: *judge independent* → separate scripts run in a subprocess;
*deterministic rules* → no "looks right" anywhere, every check is a command or a regex; *build may not
edit acceptance* → the spec hash + judge fingerprint.

## Step 4 — damping

Attempt cap **3** per card → `escalated`; `blocked` never increments; the judge itself cannot approve
(`signoff` is a separate command that requires `--by NAME`); a stale approval is impossible because
signoff re-verifies the hashes; state changes are one-way apart from the human-only `reset`.

## Step 5 — landing in three stages

1. **By hand — done.** Cards #01/#04/#07/#12/#22/#23/#26 were built this way (7 EAs, magic
   3201–3207); that run is what the checks, boundaries and rule tables were extracted from.
2. **Hardened into this runner — current.** `plan`/`build`/`judge`/`signoff` + `tests/test_cf_loop.py`.
3. **Scheduled / unattended — not yet, deliberately.** The remaining 40 cards still get a human
   signoff, and nothing is allowed to auto-merge.

## Log

* 2026-10-07 — loop landed; 7 built cards judged → `awaiting_human`, 40 planned.
* 2026-10-07 — card **#02 `80-20-nasdaq-strategy`** built (`EA_CF_8020NasdaqStrategy.mq5`, magic 3208),
  29 doc rules pinned, all gates pass → `awaiting_human`.
* 2026-10-07 — card **#03 `algorithmic-strategy`** is a *process* document (how to build, rank and
  monitor algorithms), so it delivered a monitor instead of invented entries:
  `EA_CF_AlgoPortfolioMonitor.mq5` (magic 3209, never trades) ranks the account's live algorithms
  per magic against the document's own filters — PF 1.5+, return/DD 4:1, 2+ trades/month, average
  loss ≤ 0.5 %, implied allocation 5-25 %, drawdown past 20-25 %, expectancy — into
  `cf_algo_ranking.csv`. 15 rules pinned; all gates pass → `awaiting_human`.
* 2026-10-07 — batch 1 of the grind: cards **#05 `auction-market-strategy`**
  (`EA_CF_AuctionMarket.mq5`, magic 3210, 19 rules) and **#06 `auction-market-theory-strategy`**
  (`EA_CF_AuctionMarketTheory.mq5`, magic 3211, 17 rules). Both build a tick-volume value profile
  (POC / value area / LVN) locally, since the engine has no profile primitive; #06 also carries the
  playbook's own order-flow exit as a custom `Manage()`. All gates pass → `awaiting_human`.
  **Batch workflow:** because each card's fingerprint freezes the *other* cards' rule tables, a batch
  that adds several tables runs `plan --all --reason ...` once after the tables are in, then
  `handoff` + `judge` per card. Failing a card for the batch's own table addition would be a false
  positive; the re-plan records it instead.
* 2026-10-07 — batch 2: card **#09 `fair-pricing-theory-strategy`**
  (`EA_CF_FairPricingTheory.mq5`, magic 3213, 17 rules, M1). Static TP-first R:R (stop = TP/ratio),
  three-loss session lock, the three source windows; the A+ news-reversion setup is documented as
  needing a calendar and the session-open reversion stands in. → `awaiting_human`.
* 2026-10-07 — batch 3: cards **#08 `episodic-pivot-strategy`** (`EA_CF_EpisodicPivot.mq5`, magic 3212,
  19 rules: neglect + catalyst footprint + day-1 OR break, EP 9M, delayed reaction long/short, daily-low
  trail) and **#10 `first-red-day`** (`EA_CF_FirstRedDay.mq5`, magic 3214, 13 rules: short the first
  close below the red-to-green line after a 3+ day run).  Both → `awaiting_human`.
* Fingerprint scheme **v3**: the sync test's module docstring joined the rule table as a per-card
  surface (a build records its `[interpretation]` notes there), so the frozen machinery is now the
  judging logic alone. Two further fingerprints bugs were found by this migration and fixed with
  tests — and a test of mine that had `rmtree`d the whole `tests/` directory was caught by the
  suite failing, repaired from git, and rewritten to scope its temp dir properly.
* Two loop bugs surfaced and were fixed while working #02, each with a regression test:
  the boundary fingerprint froze the *whole* sync test (so a build could never add its own card's rule
  table) → now freezes machinery + other cards; and `plan --all` was not idempotent (a second run
  exhausted the magic block) → allocation and rule floor are now preserved across re-plans.

## Review — the five failure modes against this loop

| # | Failure mode | Antibody here |
|---|---|---|
| 1 | vague goal → spins | every check is a command; `plan` refuses unknown check ids |
| 2 | self-verification → "looks fine" | judge = separate scripts + subprocess + exit codes; the builder can add its own card's rule table but cannot touch the checker, the test machinery, or another card's rules (`judge_fingerprint`, per-card) |
| 3 | only "tests pass" → the agent deletes tests | boundaries: spec hash, judge fingerprint, test-file deletion check, rule floor that cannot be lowered after judging |
| 4 | expects runtime clarification → runs the wrong answer | clarifications are front-loaded into the card's Tracking block (`card_tracking` fails while it is `_TBD_`) and into the spec at plan time |
| 5 | stale docs/memory → the faster it loops, the more it errs | the card is regenerated by `gen_todos.py` from the manifest and the checkboxes; the rule table lives next to the source it grades; `status --write` refreshes this file from state |

**Red lines:** the human flips `done`; responsibility does not transfer (the loop never merges,
never publishes, never trades); and because this loop *can* edit its own rule table, review sits
**before** the action — the judge fingerprint invalidates any card whose grading scripts changed.

## Commands

```bash
python3 chartfanatics/loop/cf_loop.py status [--write]   # board of loop states (--write refreshes this file)
python3 chartfanatics/loop/cf_loop.py next               # the card to work next + its dispatch
python3 chartfanatics/loop/cf_loop.py plan <slug>|--all  # card -> spec (magic, source, acceptance)
python3 chartfanatics/loop/cf_loop.py build <slug>       # dispatch: what to write, what is judged
python3 chartfanatics/loop/cf_loop.py judge <slug>|--pending
python3 chartfanatics/loop/cf_loop.py signoff <slug> --by "Your Name"   # HUMAN: flips done
python3 chartfanatics/loop/cf_loop.py reset <slug> --by "Your Name"     # after an escalation
```

Windows stage (owed for every card before real money): deploy the family to `MQL5\Experts\chartfanatics\`,
run `validation/mt5_harness/compile_all.ps1`, run the tester sweep, then
`judge <slug> --reports-dir <dir with EA_TestReports>`.

## Status

<!-- loop:status -->
**awaiting_human**: 14 · **planned**: 33

| card | loop state | attempts | signed off by | spec |
|---|---|---|---|---|
| `5-stage-trading-framework` | awaiting_human | 1 | — | yes |
| `80-20-nasdaq-strategy` | awaiting_human | 1 | — | yes |
| `algorithmic-strategy` | awaiting_human | 1 | — | yes |
| `amd-model` | awaiting_human | 1 | — | yes |
| `auction-market-strategy` | awaiting_human | 1 | — | yes |
| `auction-market-theory-strategy` | awaiting_human | 1 | — | yes |
| `break-retest` | awaiting_human | 1 | — | yes |
| `episodic-pivot-strategy` | awaiting_human | 1 | — | yes |
| `fair-pricing-theory-strategy` | awaiting_human | 1 | — | yes |
| `first-red-day` | awaiting_human | 1 | — | yes |
| `first-red-day-strategy` | planned | 0 | — | yes |
| `full-psychology-masterclass` | planned | 0 | — | yes |
| `futures-trading-strategy` | planned | 0 | — | yes |
| `institutional-options-flow-gamma-reversal-strategy` | planned | 0 | — | yes |
| `institutional-strategy-development-framework` | planned | 0 | — | yes |
| `intraday-liquidity-volatility-model` | awaiting_human | 1 | — | yes |
| `liquidity-inversion-model` | planned | 0 | — | yes |
| `liquidity-strategy` | planned | 0 | — | yes |
| `low-volume-node` | planned | 0 | — | yes |
| `market-auction-theory` | planned | 0 | — | yes |
| `market-dna-strategy` | planned | 0 | — | yes |
| `mean-reversion-strategy` | planned | 0 | — | yes |
| `measured-move-trend-strategy` | planned | 0 | — | yes |
| `momentum-model-performance-development` | planned | 0 | — | yes |
| `nasdaq-ict-and-order-flow-scalping-strategy` | planned | 0 | — | yes |
| `nq-liquidity-sweep-reversal-scalping-strategy` | planned | 0 | — | yes |
| `options-trading-masterclass` | planned | 0 | — | yes |
| `order-flow-strategy` | planned | 0 | — | yes |
| `orderflow-trading-masterclass` | planned | 0 | — | yes |
| `parabolic-short-strategy` | planned | 0 | — | yes |
| `po3-ote-adr` | awaiting_human | 1 | — | yes |
| `price-action-strategy` | planned | 0 | — | yes |
| `price-cycle-continuation-failed-base-strategy` | planned | 0 | — | yes |
| `real-simple-strategy` | planned | 0 | — | yes |
| `shorting-strategy` | planned | 0 | — | yes |
| `small-cap-short-statistics` | planned | 0 | — | yes |
| `smt-divergence-po3` | awaiting_human | 1 | — | yes |
| `stage-analysis-strategy` | planned | 0 | — | yes |
| `structure-ote` | awaiting_human | 1 | — | yes |
| `support-and-resistance` | planned | 0 | — | yes |
| `the-vix-futures-strategy` | planned | 0 | — | yes |
| `trading-first-principles-framework` | planned | 0 | — | yes |
| `trendline-break-pocket-strategy` | planned | 0 | — | yes |
| `trendline-strategy` | planned | 0 | — | yes |
| `unique-high-rr` | planned | 0 | — | yes |
| `universal-strategy` | planned | 0 | — | yes |
| `volume-profile-strategy` | planned | 0 | — | yes |
<!-- /loop:status -->
