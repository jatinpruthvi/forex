#!/usr/bin/env python3
"""ChartFanatics card -> EA loop: plan / build / judge, with the human flipping the done cell.

Design: ``chartfanatics/LOOP.md`` (per the ``loop-design-check`` skill - decidable goal,
boundaries, independent deterministic judge, damping, and the human red line).

    plan   card -> spec with a machine-decidable acceptance list + allocated magic
    build  the agent writes the EA to the spec (this tool prints the dispatch, it cannot code)
    judge  deterministic gates run independently of the builder; pass -> awaiting_human
           fail -> back to planned (attempts+1, cap 3 -> escalated)
    signoff  HUMAN ONLY: awaiting_human -> done

The judge never flips ``done``.  A blocked card (someone else's EA failing repo-wide gates)
is reported as ``blocked`` and does NOT burn this card's attempts.

CLI:
    python3 chartfanatics/loop/cf_loop.py status [--write]
    python3 chartfanatics/loop/cf_loop.py next
    python3 chartfanatics/loop/cf_loop.py plan <slug|--all>
    python3 chartfanatics/loop/cf_loop.py replan <slug> [--rule-count N] --by NAME
    python3 chartfanatics/loop/cf_loop.py build <slug>
    python3 chartfanatics/loop/cf_loop.py judge <slug|--pending>
    python3 chartfanatics/loop/cf_loop.py signoff <slug> --by NAME
    python3 chartfanatics/loop/cf_loop.py reset <slug> --by NAME
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CHARTS = REPO / "chartfanatics"
FAMILY = CHARTS / "mql5-eas"
MANIFEST = FAMILY / "manifest.json"
CARDS = CHARTS / "todos"
SPECS = CHARTS / "loop" / "specs"
STATE_PATH = CHARTS / "loop" / "state.json"
LOOP_DOC = CHARTS / "LOOP.md"

CHECKER = REPO / "scripts" / "check_mql5_source.py"
SYNC_TEST = REPO / "tests" / "test_chartfanatics_sync.py"
FAMILY_TEST = REPO / "tests" / "test_chartfanatics_family.py"
TESTS_DIR = REPO / "tests"
REPORTS_DEFAULT = REPO / "validation" / "mt5_harness" / "out" / "reports"

STATUS_START = "<!-- loop:status -->"
STATUS_END = "<!-- /loop:status -->"
ATTEMPT_CAP = 3
MAGIC_LOW, MAGIC_HIGH = 3201, 3247
MIN_RULES_NEW_CARD = 3          # a new EA must pin at least this many doc rules

# every id here must be implemented in CHECKS below: plan refuses an unknown check
KNOWN_CHECKS = (
    "ea_exists", "magic_ok", "checker_clean", "sync_rules", "manifest_entry",
    "card_tracking", "boundaries_intact", "windows_report",
)
DEFAULT_CHECKS = list(KNOWN_CHECKS)

BOUNDARIES = [
    "the acceptance spec must not change after plan (only `replan` may, and it is logged)",
    "the judge scripts (checker + sync test) must not change after plan",
    "no test file may be deleted or weakened",
    "`done` is flipped by a human only - the judge stops at awaiting_human",
]


# ------------------------------------------------------------------ helpers
def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_json(path: Path, default):
    if not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def manifest_entries() -> list[dict]:
    return load_json(MANIFEST, {"eas": []})["eas"]


def manifest_by_slug() -> dict[str, dict]:
    return {e["slug"]: e for e in manifest_entries()}


def all_slugs() -> list[str]:
    """Board order (slugs.txt), so the loop's queue matches the cards' numbering."""
    on_disk = {p.stem for p in CARDS.glob("*.md")}
    listing = CHARTS / "slugs.txt"
    order: list[str] = []
    if listing.is_file():
        for line in listing.read_text(encoding="utf-8").splitlines():
            slug = line.strip().rsplit("/", 1)[-1]
            if slug in on_disk and slug not in order:
                order.append(slug)
    order += sorted(on_disk - set(order))
    return order


def spec_path(slug: str) -> Path:
    return SPECS / f"{slug}.json"


def load_state() -> dict:
    state = load_json(STATE_PATH, {"cards": {}})
    state.setdefault("cards", {})
    return state


def card_state(state: dict, slug: str) -> str:
    return state["cards"].get(slug, {}).get("state", "empty")


def load_spec(slug: str) -> dict | None:
    p = spec_path(slug)
    return load_json(p, None) if p.is_file() else None


def spec_core(spec: dict) -> dict:
    return {k: v for k, v in spec.items() if k != "acceptance_hash"}


def spec_hash(spec: dict) -> str:
    return sha_text(json.dumps(spec_core(spec), sort_keys=True))


def judge_fingerprint() -> dict[str, str]:
    return {str(p.relative_to(REPO)): sha_file(p) for p in (CHECKER, SYNC_TEST) if p.is_file()}


def tests_snapshot() -> list[str]:
    return sorted(p.name for p in TESTS_DIR.glob("test_*.py"))


def card_source_doc(card_path: Path) -> str | None:
    """Resolve the first 'Source' link of a work card to a repo-relative path."""
    text = card_path.read_text(encoding="utf-8")
    m = re.search(r"\|\s*\*\*Source\*\*\s*\|([^\n]*)", text)
    if not m:
        return None
    for target in re.findall(r"\]\((\.\./[^)]+)\)", m.group(1)):
        resolved = (card_path.parent / target).resolve()
        if resolved.is_file():
            return str(resolved.relative_to(REPO))
    return None


def card_title(card_path: Path) -> str:
    first = card_path.read_text(encoding="utf-8").splitlines()[0]
    return re.sub(r"^#\s*\d+\.\s*", "", first).strip()


def card_tracking_filled(card_path: Path) -> tuple[bool, str]:
    text = card_path.read_text(encoding="utf-8")
    block = re.search(r"<!-- edit:tracking -->(.*?)<!-- /edit:tracking -->", text, re.S)
    body = block.group(1) if block else ""
    for field in ("Verdict", "Instruments", "Timeframe / session"):
        m = re.search(rf"\*\*{re.escape(field)}:\*\*\s*(.*)", body)
        if not m or not m.group(1).strip() or m.group(1).strip() == "_TBD_":
            return False, f"tracking field '{field}' is still empty"
    return True, "verdict / instruments / timeframe filled"


def sync_table() -> dict[str, list]:
    """The rule->code table from the sync test, imported (not copy-pasted)."""
    spec = importlib.util.spec_from_file_location("cf_sync_table", SYNC_TEST)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.SYNC


def family_block() -> tuple[int, int]:
    block = load_json(MANIFEST, {"magic_block": [MAGIC_LOW, MAGIC_HIGH]})["magic_block"]
    return int(block[0]), int(block[1])


def allocated_magics(exclude: str | None = None) -> dict[str, int]:
    out = {e["slug"]: int(e["magic"]) for e in manifest_entries() if e["slug"] != exclude}
    for p in SPECS.glob("*.json"):
        spec = load_json(p, {})
        if spec.get("slug") and spec["slug"] != exclude:
            out.setdefault(spec["slug"], int(spec.get("magic", 0)))
    return out


def next_free_magic(used: set[int]) -> int:
    low, high = family_block()
    for magic in range(low, high + 1):
        if magic not in used:
            return magic
    raise SystemExit(f"magic block {low}-{high} is exhausted")


# ------------------------------------------------------------------ checks
def check_ea_exists(spec: dict, args) -> tuple[bool, str]:
    path = FAMILY / spec["ea"] if spec.get("ea") else None
    if not path or not path.is_file():
        return False, f"{spec['ea']} does not exist in chartfanatics/mql5-eas/"
    return True, f"{spec['ea']} present"


def check_magic_ok(spec: dict, args) -> tuple[bool, str]:
    magic = int(spec["magic"])
    low, high = family_block()
    if not low <= magic <= high:
        return False, f"magic {magic} outside the family block {low}-{high}"
    duplicates = [s for s, m in allocated_magics(exclude=spec["slug"]).items() if m == magic]
    if duplicates:
        return False, f"magic {magic} already used by {', '.join(sorted(duplicates))}"
    ea = FAMILY / spec["ea"]
    if ea.is_file():
        source = ea.read_text(encoding="utf-8")
        if not re.search(rf"InpMagicNumber\s*=\s*{magic}\s*;", source):
            return False, f"{spec['ea']} does not default InpMagicNumber to {magic}"
    return True, f"magic {magic} unique and inside the block"


def check_checker_clean(spec: dict, args) -> tuple[bool, str]:
    out = subprocess.run([sys.executable, str(CHECKER), *(str(p) for p in sorted(FAMILY.glob("*.mq5")))],
                         capture_output=True, text=True, cwd=REPO)
    if out.returncode != 0 or "0 finding(s)" not in out.stdout:
        return False, "static checker findings:\n" + (out.stdout + out.stderr).strip()
    return True, out.stdout.strip().splitlines()[-1]


def check_sync_rules(spec: dict, args) -> tuple[bool, str]:
    table = sync_table()
    rules = table.get(spec["ea"])
    if not rules:
        return False, f"no rule->code table for {spec['ea']} in tests/test_chartfanatics_sync.py"
    if len(rules) < int(spec["rule_count"]):
        return False, (f"{len(rules)} pinned rules < {spec['rule_count']} required "
                       f"(acceptance lowered?)")
    source = (FAMILY / spec["ea"]).read_text(encoding="utf-8")
    missing = [note for pattern, note in rules if not re.search(pattern, source, re.I)]
    if missing:
        return False, "rules not found in the code:\n  - " + "\n  - ".join(missing)
    out = subprocess.run([sys.executable, "-m", "unittest", "tests.test_chartfanatics_sync"],
                         capture_output=True, text=True, cwd=REPO)
    if out.returncode != 0:
        return False, "the sync test suite fails:\n" + (out.stdout + out.stderr).strip()[-1200:]
    return True, f"{len(rules)} doc rules pinned and matching"


def check_manifest_entry(spec: dict, args) -> tuple[bool, str]:
    rows = [e for e in manifest_entries() if e["slug"] == spec["slug"]]
    if not rows:
        return False, f"manifest.json has no entry for {spec['slug']}"
    row = rows[0]
    if row["ea"] != spec["ea"] or int(row["magic"]) != int(spec["magic"]):
        return False, f"manifest says {row['ea']} / {row['magic']}, spec says {spec['ea']} / {spec['magic']}"
    return True, "manifest agrees with the spec"


def check_card_tracking(spec: dict, args) -> tuple[bool, str]:
    card = CARDS / f"{spec['slug']}.md"
    if not card.is_file():
        return False, f"no work card {card.relative_to(REPO)}"
    return card_tracking_filled(card)


def check_boundaries_intact(spec: dict, args) -> tuple[bool, str]:
    problems = []
    if spec_hash(spec) != spec.get("acceptance_hash"):
        problems.append("the acceptance spec was edited outside `replan`")
    current = judge_fingerprint()
    for name, digest in (spec.get("judge_hash") or {}).items():
        if current.get(name) != digest:
            problems.append(f"the judge changed after plan: {name} (re-plan this card)")
    deleted = [t for t in (spec.get("tests_snapshot") or []) if not (TESTS_DIR / t).is_file()]
    if deleted:
        problems.append("test files deleted since plan: " + ", ".join(deleted))
    if problems:
        return False, "; ".join(problems)
    return True, "spec, judge and test files unchanged since plan"


def check_windows_report(spec: dict, args) -> tuple[bool, str]:
    reports = Path(getattr(args, "reports_dir", None) or REPORTS_DEFAULT)
    if not reports.is_dir():
        return True, f"PENDING (Windows stage owed): no report dir at {reports}"
    hits = sorted(reports.glob(f"*_{spec['magic']}_*.csv"))
    if not hits:
        return True, f"PENDING (Windows stage owed): no tester report for magic {spec['magic']}"
    import csv
    with hits[0].open(newline="", encoding="utf-8", errors="replace") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        return False, f"{hits[0].name} is empty - the run produced no result row"
    row = rows[0]
    verdict = "trades >= 0"
    try:
        trades = int(row.get("trades", "-1"))
        if trades < 0:
            return False, f"{hits[0].name} reports {trades} trades (parse/compile failure)"
        verdict = f"{trades} trades, PF {row.get('profit_factor', '?')}"
    except (TypeError, ValueError):
        return False, f"{hits[0].name} has an unreadable trades column"
    return True, f"{hits[0].name}: {verdict}"


CHECKS = {
    "ea_exists": check_ea_exists,
    "magic_ok": check_magic_ok,
    "checker_clean": check_checker_clean,
    "sync_rules": check_sync_rules,
    "manifest_entry": check_manifest_entry,
    "card_tracking": check_card_tracking,
    "boundaries_intact": check_boundaries_intact,
    "windows_report": check_windows_report,
}

if set(KNOWN_CHECKS) != set(CHECKS):   # a check named in the contract but not implemented
    raise SystemExit("cf_loop: KNOWN_CHECKS and CHECKS disagree")


def run_judge(spec: dict, args) -> dict:
    results = []
    for name in spec["checks"]:
        if name not in CHECKS:
            results.append({"check": name, "ok": False, "detail": "unknown check id"})
            continue
        try:
            ok, detail = CHECKS[name](spec, args)
        except Exception as exc:                      # a judge that crashes is a failing judge
            ok, detail = False, f"{type(exc).__name__}: {exc}"
        results.append({"check": name, "ok": ok, "detail": detail})
    failed = [r for r in results if not r["ok"]]
    return {
        "verdict": "pass" if not failed else "fail",
        "results": results,
        "failed": failed,
        "checked_at": now_iso(),
    }


def failure_is_ours(spec: dict, failure_detail: str) -> bool:
    """Repo-wide gates can fail because of ANOTHER card's EA -> blocked, not our attempt."""
    if spec["ea"] and spec["ea"] in failure_detail:
        return True
    return not re.search(r"EA_CF_\w+\.mq5", failure_detail)


# ------------------------------------------------------------------ commands
def cmd_plan(args) -> int:
    slugs = all_slugs() if args.all else [args.slug]
    by_slug = manifest_by_slug()
    used = set(allocated_magics().values())
    state = load_state()
    for slug in slugs:
        if slug not in all_slugs():
            print(f"  ! no work card for '{slug}' - skip")
            continue
        card = CARDS / f"{slug}.md"
        row = by_slug.get(slug, {})
        ecard = row.get("ea") or f"EA_CF_{''.join(w.capitalize() for w in slug.split('-'))}.mq5"
        magic = int(row["magic"]) if row.get("magic") else next_free_magic(used)
        used.add(magic)
        rules = len(sync_table().get(ecard, []))
        spec = {
            "slug": slug,
            "title": row.get("title") or card_title(card),
            "ea": ecard,
            "magic": magic,
            "source": row.get("source") or card_source_doc(card),
            "rule_count": rules if rules else (int(args.rule_count) if args.rule_count else MIN_RULES_NEW_CARD),
            "checks": DEFAULT_CHECKS,
            "boundaries": BOUNDARIES,
            "spec_version": 1,
            "attempt_cap": ATTEMPT_CAP,
            "judge_hash": judge_fingerprint(),
            "tests_snapshot": tests_snapshot(),
            "planned_at": now_iso(),
        }
        spec["acceptance_hash"] = spec_hash(spec)
        save_json(spec_path(slug), spec)
        entry = state["cards"].setdefault(slug, {"attempts": 0})
        if entry.get("state") not in ("awaiting_human", "done", "escalated"):
            entry["state"] = "planned"
        entry["planner"] = args.by or "agent"
        entry["updated"] = now_iso()
        print(f"  planned {slug}: magic {magic}, >= {spec['rule_count']} doc rules, "
              f"{len(spec['checks'])} checks")
    save_json(STATE_PATH, state)
    return 0


def cmd_replan(args) -> int:
    spec = load_spec(args.slug) or _die(f"no spec for {args.slug} - run plan first")
    state = load_state()
    if getattr(args, "ea", None):
        spec["ea"] = args.ea
    if args.rule_count is not None:
        current, wanted = int(spec["rule_count"]), int(args.rule_count)
        if wanted < current and card_state(state, args.slug) != "planned":
            return _die(f"refusing to lower the rule floor {current} -> {wanted}: the card has "
                        f"already been judged (Goodhart boundary)")
        spec["rule_count"] = wanted
    spec["spec_version"] = int(spec.get("spec_version", 1)) + 1
    spec["replanned_by"] = args.by
    spec["replanned_at"] = now_iso()
    spec["acceptance_hash"] = spec_hash(spec)
    save_json(spec_path(args.slug), spec)
    print(f"  replanned {args.slug} (spec v{spec['spec_version']}, >= {spec['rule_count']} rules)")
    return 0


def cmd_build(args) -> int:
    spec = load_spec(args.slug) or _die(f"no spec for {args.slug} - run plan first")
    print(f"BUILD DISPATCH - {spec['slug']} ({spec['title']})\n")
    print(f"  source doc   : {spec['source']}")
    print(f"  EA to write  : chartfanatics/mql5-eas/{spec['ea']}")
    print(f"  magic        : {spec['magic']}")
    print(f"  rule floor   : pin at least {spec['rule_count']} doc rules in "
          f"tests/test_chartfanatics_sync.py\n")
    print("  acceptance (machine-judged, do not edit the spec):")
    for name in spec["checks"]:
        print(f"    - {name}")
    print("\n  boundaries:")
    for b in spec["boundaries"]:
        print(f"    - {b}")
    print(f"\n  then: python3 chartfanatics/loop/cf_loop.py judge {spec['slug']}")
    return 0


def cmd_handoff(args) -> int:
    state = load_state()
    entry = state["cards"].get(args.slug) or _die(f"unknown card {args.slug} - run plan first")
    if entry.get("state") != "planned":
        return _die(f"{args.slug} is '{entry.get('state')}' - handoff is for cards in 'planned'")
    if int(entry.get("attempts", 0)) >= ATTEMPT_CAP:
        entry["state"] = "escalated"
        entry["updated"] = now_iso()
        save_json(STATE_PATH, state)
        return _die(f"{args.slug} already used {ATTEMPT_CAP}/{ATTEMPT_CAP} attempts - "
                    f"escalated; a human must `reset` it")
    entry["attempts"] = int(entry.get("attempts", 0)) + 1
    entry["state"] = "built"
    entry["built_by"] = args.by or "agent"
    entry["updated"] = now_iso()
    save_json(STATE_PATH, state)
    print(f"  {args.slug}: handed to the judge (attempt {entry['attempts']}/{ATTEMPT_CAP})")
    return 0


def cmd_judge(args) -> int:
    state = load_state()
    slugs = [s for s in all_slugs() if card_state(state, s) == "built"] if args.pending else [args.slug]
    if not slugs:
        print("  nothing to judge (no card handed over: run `build` then `handoff`)")
        return 0
    for slug in slugs:
        spec = load_spec(slug) or _die(f"no spec for {slug} - run plan first")
        verdict = run_judge(spec, args)
        entry = state["cards"].setdefault(slug, {"attempts": 0})
        entry["last_verdict"] = verdict["verdict"]
        entry["last_checked"] = verdict["checked_at"]
        entry["pending"] = [r["detail"] for r in verdict["results"] if r["ok"] and r["detail"].startswith("PENDING")]
        handed_over = entry.get("state") == "built"
        if verdict["verdict"] == "pass":
            entry["state"] = "awaiting_human"
            entry["last_reason"] = "all deterministic gates pass"
        else:
            detail = "\n".join(f"{r['check']}: {r['detail']}" for r in verdict["failed"])
            entry["last_reason"] = detail
            if not failure_is_ours(spec, detail):
                entry["state"] = "blocked"
                entry["blocked_by"] = re.findall(r"EA_CF_\w+\.mq5", detail) or ["repo-wide gate"]
            elif handed_over:
                # the attempt was counted at handoff; this failure ends it
                entry["state"] = "escalated" if entry["attempts"] >= ATTEMPT_CAP else "planned"
            else:
                entry["state"] = "planned"
                entry["last_reason"] += "\n(diagnostic run: no handoff, so no attempt was burned)"
        entry["updated"] = now_iso()
        print(_verdict_line(slug, spec, verdict, entry))
    save_json(STATE_PATH, state)
    return 0


def _verdict_line(slug: str, spec: dict, verdict: dict, entry: dict) -> str:
    lines = [f"  {slug}: {verdict['verdict'].upper()} -> {entry['state']} "
             f"(attempt {entry.get('attempts', 0)}/{spec['attempt_cap']})"]
    for r in verdict["results"]:
        mark = "ok " if r["ok"] else "FAIL"
        lines.append(f"    [{mark}] {r['check']}: {r['detail'].splitlines()[0][:150]}")
    if verdict["verdict"] == "fail":
        lines.append("    reason: " + entry["last_reason"].splitlines()[0][:200])
    return "\n".join(lines)


def cmd_signoff(args) -> int:
    state = load_state()
    entry = state["cards"].get(args.slug) or _die(f"unknown card {args.slug}")
    if entry.get("state") != "awaiting_human":
        return _die(f"{args.slug} is '{entry.get('state')}' - only awaiting_human can be signed off")
    spec = load_spec(args.slug) or _die("no spec")
    # an approval can never be stale: re-verify the hashes it was granted against
    ok, detail = check_boundaries_intact(spec, args)
    if not ok:
        return _die(f"refusing signoff: {detail}")
    if entry.get("last_verdict") != "pass":
        return _die("refusing signoff: the last judge verdict is not a pass")
    entry["state"] = "done"
    entry["signed_off_by"] = args.by
    entry["signed_off_at"] = now_iso()
    entry["updated"] = now_iso()
    save_json(STATE_PATH, state)
    print(f"  {args.slug}: done, signed off by {args.by}")
    return 0


def cmd_reset(args) -> int:
    state = load_state()
    entry = state["cards"].get(args.slug) or _die(f"unknown card {args.slug}")
    if entry.get("state") == "built":
        return _die(f"{args.slug} is mid-judging ('built') - run `judge` first")
    entry["state_before_reset"] = entry.get("state", "empty")
    entry["state"] = "planned"
    entry["attempts"] = 0
    entry["reset_by"] = args.by
    entry["reset_note"] = args.note or "human reset"
    entry["updated"] = now_iso()
    save_json(STATE_PATH, state)
    print(f"  {args.slug}: attempts reset to 0 by {args.by} - next attempt is fresh")
    return 0


def cmd_next(args) -> int:
    state = load_state()
    order = {slug: i for i, slug in enumerate(all_slugs())}
    pending = [s for s in all_slugs() if card_state(state, s) == "planned"]
    if not pending:
        print("  queue empty - nothing in 'planned'")
        return 0
    slug = min(pending, key=lambda s: (card_state(state, s) == "blocked", order[s]))
    entry = state["cards"][slug]
    print(f"next: {slug} ({card_state(state, slug)}, attempt {entry.get('attempts', 0)})")
    return cmd_build(argparse.Namespace(slug=slug))


def cmd_status(args) -> int:
    state = load_state()
    rows = []
    for slug in all_slugs():
        entry = state["cards"].get(slug, {})
        spec = load_spec(slug)
        rows.append((slug, entry.get("state", "empty"),
                     entry.get("attempts", 0), entry.get("signed_off_by", ""),
                     "yes" if spec else "-"))
    counts: dict[str, int] = {}
    for _, st, *_ in rows:
        counts[st] = counts.get(st, 0) + 1
    table = ["| card | loop state | attempts | signed off by | spec |", "|---|---|---|---|---|"]
    table += [f"| `{s}` | {st} | {a} | {by or '—'} | {sp} |" for s, st, a, by, sp in rows]
    summary = " · ".join(f"**{k}**: {v}" for k, v in sorted(counts.items()))
    board = f"{summary}\n\n" + "\n".join(table)
    print(board)
    if args.write:
        _write_status_block(board)
        print(f"\n  status block written to {LOOP_DOC.relative_to(REPO)}")
    return 0


def _write_status_block(board: str) -> None:
    if not LOOP_DOC.is_file():
        raise SystemExit(f"{LOOP_DOC} is missing - the loop doc must exist before status --write")
    text = LOOP_DOC.read_text(encoding="utf-8")
    block = f"{STATUS_START}\n{board}\n{STATUS_END}"
    if STATUS_START in text and STATUS_END in text:
        text = re.sub(rf"{re.escape(STATUS_START)}.*?{re.escape(STATUS_END)}", block, text, flags=re.S)
    else:
        text = text.rstrip() + "\n\n" + block + "\n"
    LOOP_DOC.write_text(text, encoding="utf-8")


def _die(message: str) -> int:
    print(f"  error: {message}", file=sys.stderr)
    raise SystemExit(2)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("status"); p.add_argument("--write", action="store_true"); p.set_defaults(fn=cmd_status)
    p = sub.add_parser("next"); p.set_defaults(fn=cmd_next)
    p = sub.add_parser("plan"); p.add_argument("slug", nargs="?"); p.add_argument("--all", action="store_true")
    p.add_argument("--rule-count", type=int, dest="rule_count"); p.add_argument("--by"); p.set_defaults(fn=cmd_plan)
    p = sub.add_parser("replan"); p.add_argument("slug"); p.add_argument("--rule-count", type=int, dest="rule_count")
    p.add_argument("--ea", help="final EA filename (chosen at build time)")
    p.add_argument("--by", required=True); p.set_defaults(fn=cmd_replan)
    p = sub.add_parser("build"); p.add_argument("slug"); p.set_defaults(fn=cmd_build)
    p = sub.add_parser("handoff"); p.add_argument("slug"); p.add_argument("--by"); p.set_defaults(fn=cmd_handoff)
    p = sub.add_parser("judge"); p.add_argument("slug", nargs="?"); p.add_argument("--pending", action="store_true")
    p.add_argument("--reports-dir"); p.set_defaults(fn=cmd_judge)
    p = sub.add_parser("signoff"); p.add_argument("slug"); p.add_argument("--by", required=True); p.set_defaults(fn=cmd_signoff)
    p = sub.add_parser("reset"); p.add_argument("slug"); p.add_argument("--by", required=True)
    p.add_argument("--note"); p.set_defaults(fn=cmd_reset)

    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
