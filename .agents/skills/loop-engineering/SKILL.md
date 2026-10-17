---
name: loop-engineering
description: Use when handed a multi-step task that must be proven with evidence before it is called finished - delegated code changes, backtest or strategy validation runs, investigations with acceptance criteria. Runs a bounded DISCOVER, SCOPE, PLAN, IMPLEMENT, VERIFY, REVISE-or-REPORT loop against a per-project profile. Not for one-line edits, releases, deployments, or destructive actions.
---

# Loop Engineering

One reusable workflow. Project rules live in a **profile**, agent quirks live in an **adapter**.

```
DISCOVER -> SCOPE -> PLAN -> IMPLEMENT -> VERIFY -> REVISE (max 3x) or REPORT
```

This skill was written from scratch for this repository. It copies no text from any other project's skill.

## 0. Load the profile first

1. Read `projects/<name>.md` next to this file. For this repo: `projects/forex-strategy-validation.md`.
2. Read your agent's adapter in `adapters/` (tool names, where to run commands, how to delegate).
3. **No profile for this project?** Copy `projects/_template.md`, fill what you can discover, and treat every
   unfilled "approval" field as **ask first**. Until a profile exists, stay read-only plus local scratch files.

The profile is the source of truth for: docs to read, run/test commands, baselines, data rules,
where plans and results go, what needs approval, and git rules. This file never overrides it.

## 1. When to use / not use

**Use** when the task has 2+ steps, touches shared artifacts, or ends in a claim ("it works", "it passes",
"the strategy holds") that someone will rely on.

**Do not use** for: a typo or one-line fix, pure Q&A, or anything where the user already gave exact commands.
Just do those.

**Never do inside the loop without explicit approval** (profiles add to this list, never remove):
- releases, deployments, publishing, force-push, deleting or rewriting history, deleting branches
- deleting, renaming, or overwriting data or frozen artifacts the profile marks as frozen
- changing the verifier, thresholds, or acceptance criteria to make a failing result pass
- spending real money, touching credentials, or contacting live systems

## 2. The phases

### DISCOVER (read only)
- Read the profile's required docs. Run `git status`; note unrelated dirty files and **leave them alone**.
- Run the baseline verification **before touching anything** and record it (pass/fail counts, known failures).
  A failure that exists at baseline is not yours to fix silently - list it in the report.
- Exit when you can state, in 3 lines: the goal, what exists, and what is unknown.

### SCOPE
- Write **acceptance criteria** as checks a command can decide: "`X` exits 0", "metric M on window W is >= T".
  If a criterion needs judgment, mark it **human-judged** and do not self-approve it.
- Write **non-goals** and the **budget**: max repair cycles (default 3 per criterion), max trials or
  configurations if the work is a search, max wall-clock/commands if relevant.
- Thresholds are fixed **now**, before results exist. They may be tightened later, never loosened by you.
- Ambiguity rule: if two readings would lead to materially different work, or one is irreversible, **ask**.
  Otherwise pick the safer reading, write the assumption down, continue.

### PLAN
- Smallest ordered steps, each with the check that proves it. Say which files you will change.
- Anything on the approval list goes in the plan as "needs approval" - do not defer it to the end.
- Skip a written plan only for tasks of 3 steps or fewer. Never skip criteria.

### IMPLEMENT
- One logical change at a time. Keep diffs inside the plan. New behavior gets a test where the project has tests.
- Do not "fix" adjacent things you noticed; add them to the report as follow-ups.

### VERIFY (fresh evidence only)
- Run the profile's verification commands **after your last edit**. Evidence from before an edit does not count.
- Verify against each acceptance criterion by name. Paste or cite real output (counts, exit codes, numbers).
- The verifier must be independent of the thing verified: do not edit tests, fixtures, thresholds, or data
  in the same change you use them to judge, unless approved.
- "Too good" results are a **failure signal**, not a success: investigate the profile's suspicion triggers first.

### REVISE (bounded)
- Each repair cycle must state: what failed, the hypothesis for why, the one change that tests it.
- **Same failure twice = stop guessing.** Re-read the evidence, change approach, or escalate.
- **3 failed repair cycles on one criterion = stop the loop** and report PARTIAL or BLOCKED.
  Do not start a fourth "one more try".
- Repairing an implementation defect is different from trying another parameter set. Parameter trials
  spend the search budget from SCOPE; see the profile for the multiple-testing rules.

### REPORT
Finish with exactly one terminal status:

| Status | Meaning |
|---|---|
| **DONE** | Every criterion checked by fresh evidence; no open blocker. Say what was run. |
| **PARTIAL** | Some criteria proven, some not. List each with the reason (budget, blocked, human-judged). |
| **BLOCKED** | Cannot proceed: missing access/data/approval/decision, or the repair limit hit. State exactly what unblocks it. |

Report template: status, criteria table (criterion, evidence, result), what changed (files), what was
run (commands), baseline failures left alone, assumptions made, follow-ups, and next decision for the human.

Never write "should work", "looks good", or "tests pass" without the run that shows it.

## 3. Stop and ask when
- a required approval, credential, dataset, or decision is missing
- the working tree has unrelated changes that overlap the files you need
- verification cannot run in this environment (say so; do not substitute a weaker check silently)
- the goal itself looks wrong (a criterion is unmeetable, or the result contradicts the premise)
- you catch yourself about to change a threshold, a test, or a data file to get a green result

## 4. Ledger
Keep a short running ledger (template: `templates/loop-ledger.md`) in the location the profile names.
One line per iteration: what was tried, evidence, decision. It is how a cold-start agent resumes, and how
a reviewer sees the search that produced a result.

## 5. Testing this skill
`tests/scenarios.md` lists pressure scenarios with the expected safe behavior. Re-run them against each
adapter whenever this file or a profile changes. Scenario checks are about *stopping correctly*, not prose quality.

One canonical copy lives here; agents that look elsewhere get a symlink or a synced copy (see "Keeping in sync" in `tests/scenarios.md`).

## Layout
```
loop-engineering/
  SKILL.md                       this file - portable workflow
  adapters/                      thin per-agent notes (discovery path, tool mapping)
  projects/                      one profile per project (+ _template.md)
  templates/loop-ledger.md       iteration ledger
  scripts/preflight_data.py      forex profile helper (stdlib only)
  tests/scenarios.md             pressure scenarios
```
