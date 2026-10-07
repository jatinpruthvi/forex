#!/usr/bin/env python3
"""Generate and maintain the ChartFanatics strategy work tracker.

Produces, for every strategy published on chartfanatics.com/strategies (47):

  todos/<slug>.md   one "card" per strategy, with an 8-stage delivery checklist
  TODO.md           master board: status + progress for all 47, grouped by source type

Re-running is safe: everything between the <!-- edit:... --> markers is preserved
verbatim (checkbox states, Tracking fields, Notes), so this is an update tool, not a
one-shot scaffold.

Local metadata only - no network access:
  slugs.txt   slug -> strategy name -> Google Drive PDF link
  novid.txt   video-only strategies: slug, name, YouTube id, source channel
  README.md   video-only strategies: glimpse summary slug + markdown + rendered PDF
  pdf/        downloaded PDFs (name == slug)
  glimpse/    Glimpse markdown summaries
  glimpse-pdf/  rendered PDFs of those summaries

Usage:
  python3 gen_todos.py
"""
from __future__ import annotations

import datetime as dt
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TODOS = ROOT / "todos"

# --------------------------------------------------------------------------------------
# The 8 delivery stages. (id, title, detail)
# --------------------------------------------------------------------------------------
STAGES = [
    ("read", "Read source", "PDF / summary reviewed end to end; note page or section refs in Notes"),
    ("extract", "Extract rules", "Entry, exit, stop, targets, timeframe, session, instruments - in writing"),
    ("verdict", "Mechanizable?", "Verdict: EA candidate | discretionary checklist | drop (say why)"),
    ("spec", "Write spec", "Unambiguous spec: exact conditions, no 'price reacts' phrasing"),
    ("backtest", "Backtest", "Run through validation/mt5_harness; record symbol, period, PF, DD, trades"),
    ("ea", "Implement EA", "New .mq5 with its own magic, or adapt an existing engine; cross-check docs/ICT_SMC_COVERAGE.md"),
    ("validate", "Validate", "Strategy Tester gates + scripts/check_mql5_source.py pass"),
    ("demo", "Demo / forward", "Forward phase per docs/EA_VALIDATION_PLAYBOOK.md, then live decision"),
]
STAGE_IDS = [s[0] for s in STAGES]

STATUS_ICON = {"todo": "⬜", "wip": "🟡", "done": "✅"}


def bar(done: int, total: int, width: int | None = None) -> str:
    """Progress bar; width caps the length (scaled) for large totals."""
    if width and total > width:
        filled = round(done / total * width) if total else 0
        return "▰" * filled + "▱" * (width - filled)
    return "▰" * done + "▱" * (total - done)


# --------------------------------------------------------------------------------------
# Metadata
# --------------------------------------------------------------------------------------
def read_links() -> dict[str, dict]:
    """slugs.txt -> {slug: {name, drive}} (tab separated, drive may be empty)."""
    out = {}
    for line in (ROOT / "slugs.txt").read_text(encoding="utf-8").splitlines():
        slug = line.strip().split("/")[-1]
        if slug:
            out[slug] = {"slug": slug, "name": "", "drive": ""}
    for line in (ROOT / "links.txt").read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        slug = parts[0].strip()
        if slug in out:
            out[slug]["name"] = parts[1].strip()
            out[slug]["drive"] = parts[2].strip() if len(parts) > 2 else ""
    return out


def read_video_only() -> dict[str, dict]:
    """novid.txt -> {slug: {video, channel}}."""
    out = {}
    for line in (ROOT / "novid.txt").read_text(encoding="utf-8").splitlines():
        parts = [p.rstrip() for p in line.split("\t")]
        if len(parts) < 4:
            continue
        out[parts[0].strip()] = {"video": parts[2].strip(), "channel": parts[3].strip()}
    return out


def read_glimpse_index() -> dict[str, dict]:
    """README video table -> {strategy name (lower, stripped): {slug, md, pdf}}."""
    out = {}
    text = (ROOT / "README.md").read_text(encoding="utf-8")
    row = re.compile(
        r"^\|\s*([^|]+?)\s*\|\s*\[video\]\(([^)]+)\)\s*\|\s*\[summary\]\(([^)]+)\)\s*"
        r"\|\s*\[md\]\(([^)]+)\)\s*\|\s*\[pdf\]\(([^)]+)\)\s*\|",
        re.M,
    )
    for name, video, summary, md, pdf in row.findall(text):
        out[name.strip().lower()] = {
            "glimpse": summary.rsplit("/", 1)[-1],
            "md": md.strip(),
            "pdf": pdf.strip(),
            "video": video.rsplit("=", 1)[-1],
        }
    return out


def human(size: int) -> str:
    return f"{size / 1024 / 1024:.1f} MB"


def read_ea_manifest() -> dict[str, dict]:
    """mql5-eas/manifest.json -> {slug: {ea, magic, class, ...}} (absent = no EA yet)."""
    path = ROOT / "mql5-eas" / "manifest.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {entry["slug"]: entry for entry in data.get("eas", [])}


def build_meta() -> list[dict]:
    links = read_links()
    eas = read_ea_manifest()
    vids = read_video_only()
    glim = read_glimpse_index()
    meta = []
    for slug, rec in links.items():
        name = rec["name"] or slug.replace("-", " ").title()
        m = {"slug": slug, "name": name, "number": len(meta) + 1, "pdf": None, "drive": rec["drive"],
             "video": None, "glimpse": None, "md": None, "glimpse_pdf": None, "channel": None,
             "ea": eas.get(slug)}
        pdf = ROOT / "pdf" / f"{slug}.pdf"
        if pdf.exists():
            m["pdf"] = {"path": f"../pdf/{pdf.name}", "bytes": pdf.stat().st_size}
        if slug in vids:
            m["video"] = vids[slug]["video"]
            m["channel"] = vids[slug]["channel"]
            g = glim.get(name.strip().lower(), {})
            m["glimpse"] = g.get("glimpse") or None
            m["md"] = g.get("md") or None
            m["glimpse_pdf"] = g.get("pdf") or None
        meta.append(m)
    return meta


# --------------------------------------------------------------------------------------
# Card rendering
# --------------------------------------------------------------------------------------
EDIT_BLOCK = "<!-- edit:{name} -->\n{body}\n<!-- /edit:{name} -->"


def edit_block(text: str, name: str, default: str) -> str:
    """Return the preserved body of an edit: block, or the default."""
    m = re.search(rf"<!-- edit:{name} -->\n(.*?)\n<!-- /edit:{name} -->", text, re.S)
    if not m:
        return default
    body = m.group(1)
    return body if body.strip() else default


def default_tracking(meta: dict) -> str:
    ea = meta.get("ea") or {}
    ea_line = (f"- **EA file / magic:** [`{ea['ea']}`](../mql5-eas/{ea['ea']}) / `{ea['magic']}` "
               f"({ea.get('status', 'n/a')})" if ea else "- **EA file / magic:** _unassigned_")
    return "\n".join([
        "- **Verdict:** _TBD_",
        "- **Instruments:** _TBD_",
        "- **Timeframe / session:** _TBD_",
        ea_line,
        "- **Priority:** _TBD_ (P1 = do next, P2 = queued, P3 = nice-to-have)",
        "- **Blocked by:** _nothing_",
    ])


def fill_ea_line(body: str, meta: dict) -> str:
    """Fill the EA/magic Tracking line while it is still the placeholder (never overwrite an edit)."""
    ea = meta.get("ea")
    if not ea or "_unassigned_" not in body:
        return body
    line = (f"- **EA file / magic:** [`{ea['ea']}](../mql5-eas/{ea['ea']}) / `{ea['magic']}` "
            f"({ea.get('status', 'n/a')})")
    return body.replace("- **EA file / magic:** _unassigned_", line)


def card(meta: dict, existing: str) -> str:
    """Render one strategy card, carrying over checkbox state and edited sections."""
    # checkbox state is keyed by the hidden <!-- id:... --> comment on each stage line
    states = {sid: " " for sid in STAGE_IDS}
    for sid in STAGE_IDS:
        m = re.search(rf"^- \[([ xX])\] .*<!-- id:{sid} -->$", existing, re.M)
        if m:
            states[sid] = m.group(1)

    done = sum(1 for v in states.values() if v.lower() == "x")
    status = "done" if done == len(STAGES) else ("wip" if done else "todo")

    src_parts = []
    if meta["pdf"]:
        src_parts.append(f"[PDF](../pdf/{meta['slug']}.pdf) ({human(meta['pdf']['bytes'])})")
    if meta["md"]:
        src_parts.append(f"[Glimpse summary](../{meta['md']})")
    if meta["glimpse_pdf"]:
        src_parts.append(f"[summary PDF](../{meta['glimpse_pdf']})")
    if meta["video"]:
        src_parts.append(f"[YouTube](https://www.youtube.com/watch?v={meta['video']})"
                         + (f" ({meta['channel'].replace('youtube.com/', '')})" if meta["channel"] else ""))

    link_parts = [f"[chartfanatics.com/strategies/{meta['slug']}](https://www.chartfanatics.com/strategies/{meta['slug']})"]
    if meta["drive"]:
        link_parts.append(f"[source PDF on Google Drive]({meta['drive']})")
    if meta["glimpse"]:
        link_parts.append(f"[Glimpse](https://glimpse.wozart.com/v/{meta['glimpse']})")

    head = "\n".join([
        f"# {meta['number']:02d}. {meta['name']}",
        "",
        f"| | |",
        f"|---|---|",
        f"| **Status** | {STATUS_ICON[status]} {status.upper()} — {done}/{len(STAGES)} stages |",
        f"| **Slug** | `{meta['slug']}` |",
        f"| **Type** | {'video-only (Glimpse summary)' if not meta['pdf'] else 'published PDF'} |",
        f"| **Source** | {' · '.join(src_parts)} |",
        f"| **Origin** | {' · '.join(link_parts)} |",
        f"| **Board** | [`chartfanatics/TODO.md`](../TODO.md) |",        f"| **Updated** | {dt.date.today().isoformat()} |",
    ])

    stages = "\n".join(
        f"- [{states[sid]}] **{i}. {title}** — {detail} <!-- id:{sid} -->"
        for i, (sid, title, detail) in enumerate(STAGES, 1)
    )

    return f"""{head}

> Work this card top to bottom; **tick a box in place and it survives regeneration**
> (`python3 gen_todos.py`), so the checkboxes are the source of truth for status.
> Anything between the `edit:` markers is never overwritten by the generator.

## Stages

{stages}

## Tracking

{EDIT_BLOCK.format(name='tracking', body=fill_ea_line(edit_block(existing, 'tracking', default_tracking(meta)), meta))}

## Notes

{EDIT_BLOCK.format(name='notes', body=edit_block(existing, 'notes', '_Nothing yet._'))}
"""


# --------------------------------------------------------------------------------------
# Board
# --------------------------------------------------------------------------------------
SHORTLIST_DEFAULT = """Ordered by how cheaply they can be tested against code that already exists in
`MQL5_Master/Include/EASignals.mqh` (sweep / order-block / FVG / fractal primitives) — no new
infrastructure needed to get a first verdict:

| Order | Strategy | Why first |
|---|---|---|
| 1 | [AMD Model](todos/amd-model.md) | Explicit accumulation-manipulation-distribution model; maps to the existing session-range sweep |
| 2 | [Structure + OTE](todos/structure-ote.md) | Structure break + 62-79% retrace; OTE is listed in docs/ICT_SMC_COVERAGE.md as *not implemented* — a real gap |
| 3 | [SMT Divergence + PO3](todos/smt-divergence-po3.md) | Repo has an RSI-proxy SMT that goes inert without DXY; this gives a real spec |
| 4 | [PO3, OTE + ADR](todos/po3-ote-adr.md) | Same primitives plus an ADR filter to reuse for the daily gate |
| 5 | [Break & Retest](todos/break-retest.md) | Simplest possible rule set; fast falsification |
| 6 | [Intraday Liquidity & Volatility Model](todos/intraday-liquidity-volatility-model.md) | Session/volatility window logic reusable across every engine |
"""


def ea_cell(meta: dict) -> str:
    ea = meta.get("ea")
    if not ea:
        return "_—_"
    return f"[`{ea['ea'].replace('EA_CF_', '')}`](mql5-eas/{ea['ea']}) mag {ea['magic']}"


def status_of(body: str) -> tuple[str, int]:
    done = sum(1 for sid in STAGE_IDS
               if re.search(rf"^- \[[xX]\] .*<!-- id:{sid} -->$", body, re.M))
    status = "done" if done == len(STAGES) else ("wip" if done else "todo")
    return status, done


def table(metas: list[dict], cards: dict[str, str]) -> str:
    lines = ["| # | Strategy | Status | Progress | Source | EA | Card |",
             "|---|---|---|---|---|---|---|"]
    for m in metas:
        status, done = status_of(cards[m["slug"]])
        if m["pdf"]:
            src = f"[PDF](pdf/{m['slug']}.pdf) {human(m['pdf']['bytes'])}"
        else:
            src = f"[video](https://www.youtube.com/watch?v={m['video']}) · [summary]({m['md']})"
        lines.append(
            f"| {m['number']:02d} | {m['name']} | {STATUS_ICON[status]} {status} | "
            f"`{bar(done, len(STAGES))}` {done}/{len(STAGES)} | {src} | {ea_cell(m)} | "
            f"[`{m['slug']}.md`](todos/{m['slug']}.md) |"
        )
    return "\n".join(lines)


def board(metas: list[dict], cards: dict[str, str], existing: str) -> str:
    pdf = [m for m in metas if m["pdf"]]
    vid = [m for m in metas if not m["pdf"]]
    counts = {"todo": 0, "wip": 0, "done": 0}
    stages_done = 0
    for m in metas:
        status, done = status_of(cards[m["slug"]])
        counts[status] += 1
        stages_done += done
    total_stages = len(STAGES) * len(metas)
    eas_built = sum(1 for m in metas if m.get("ea"))

    return f"""# ChartFanatics — Strategy Work Board

**{len(metas)} strategies** archived in this folder ({len(pdf)} with a published PDF, {len(vid)} video-only
with a Glimpse summary). Every strategy has a work card in [`todos/`](todos/) covering the same
8 stages, from "read the source" to "demo / forward".

**Cards:** {STATUS_ICON['done']} {counts['done']} done · {STATUS_ICON['wip']} {counts['wip']} in progress ·
{STATUS_ICON['todo']} {counts['todo']} not started

**EAs built:** {eas_built}/{len(metas)} — see [`mql5-eas/`](mql5-eas/) (magic block 3201-3247)

**Stages ticked:** {stages_done}/{total_stages} ({round(stages_done / total_stages * 100)}%)
`{bar(stages_done, total_stages, 32)}`

*Regenerated {dt.date.today().isoformat()} by [`gen_todos.py`](gen_todos.py). Checkbox state lives in each card
and is never lost on regeneration; edit through the cards, not this board.*

---

## How to work a card

1. Open `todos/<slug>.md`, read the source PDF / summary, fill the **Tracking** block with the verdict.
2. Tick stage boxes as you go — a card with any box ticked becomes 🟡, all 8 becomes ✅.
3. Re-run `python3 gen_todos.py` after ticking to refresh this board (it preserves every edit).
4. When a strategy is dropped, leave the verdict in Tracking and say why — that is as useful as an EA.

Reference material for the later stages: [`docs/EA_VALIDATION_PLAYBOOK.md`](../docs/EA_VALIDATION_PLAYBOOK.md)
(compile → calendar → tester sweep → forward), [`docs/ICT_SMC_COVERAGE.md`](../docs/ICT_SMC_COVERAGE.md)
(which primitives already exist and which are genuinely missing),
[`docs/EA_IMPLEMENTATION_TRACKER.md`](../docs/EA_IMPLEMENTATION_TRACKER.md) (magic-number allocation; anything
built here must take a free magic outside 1000-1016 / 2001-2048 / 3101-3117).

## Kickoff shortlist

{EDIT_BLOCK.format(name='shortlist', body=edit_block(existing, 'shortlist', SHORTLIST_DEFAULT))}

---

## Published PDFs ({len(pdf)})

{table(pdf, cards)}

## Video-only — no published PDF ({len(vid)})

{table(vid, cards)}

---

*Sources: [chartfanatics.com/strategies](https://www.chartfanatics.com/strategies). Video-only strategies
summarised via [Glimpse](https://glimpse.wozart.com) — see [`README.md`](README.md) for provenance and
[`glimpse.py`](glimpse.py) / [`make_pdfs.py`](make_pdfs.py) to regenerate.*
"""


# --------------------------------------------------------------------------------------
def refresh_glimpse_index(metas: list[dict]) -> None:
    """Rewrite glimpse_index.json from ground truth (md files on disk) - it had gone stale."""
    idx = []
    for m in metas:
        if not m["video"]:
            continue
        md = ROOT / "glimpse" / f"{m['video']}.md"
        idx.append({
            "videoId": m["video"],
            "strategy": m["name"],
            "glimpseSlug": m["glimpse"] or "",
            "done": md.exists() and md.stat().st_size > 200,
        })
    idx.sort(key=lambda r: r["videoId"])
    (ROOT / "glimpse_index.json").write_text(json.dumps(idx, indent=1) + "\n", encoding="utf-8")


def main() -> None:
    TODOS.mkdir(exist_ok=True)
    metas = build_meta()

    cards = {}
    created = updated = 0
    for m in metas:
        path = TODOS / f"{m['slug']}.md"
        existing = path.read_text(encoding="utf-8") if path.exists() else ""
        new = card(m, existing)
        # do not churn the Updated stamp when nothing else changed
        strip = lambda s: re.sub(r"\| \*\*Updated\*\* \| .*? \|", "", s)
        if not existing:
            path.write_text(new, encoding="utf-8")
            created += 1
        elif strip(new) != strip(existing):
            path.write_text(new, encoding="utf-8")
            updated += 1
        cards[m["slug"]] = path.read_text(encoding="utf-8")

    board_path = ROOT / "TODO.md"
    old_board = board_path.read_text(encoding="utf-8") if board_path.exists() else ""
    board_path.write_text(board(metas, cards, old_board), encoding="utf-8")

    refresh_glimpse_index(metas)
    print(f"cards: {created} created, {updated} updated, {len(metas) - created - updated} unchanged")
    print(f"board: {board_path.relative_to(ROOT.parent)} ({len(metas)} strategies)")


if __name__ == "__main__":
    main()
