#!/usr/bin/env python3
"""Generate ONE-CLICK chart templates + launcher plan for all 65 EAs.

MT5 allows exactly one EA per chart, so "running all 65" means 65 charts.
This removes the manual work: a small MQL5 script
(MQL5_Master/Scripts/PortfolioLauncher.mq5) reads ``launch_plan.csv``,
opens every chart for you and applies a per-EA template that already carries
the compiled EA *and* its inputs.  You attach ONE program, once.

Why a base template
-------------------
MT5's template file format carries the EA's live-trading permission in the
``<expert>`` block (``flags=``).  Rather than guess those bits, save ONE
template from your own terminal and this script stamps out 65 variants of it,
swapping only the EA name and the ``<inputs>`` values:

  1. Attach any EA to any chart (with "Algo Trading" ON), right-click the
     chart -> Template -> Save Template -> name it ``EA_Launch_Base``.
     (MT5 writes it to <data>\\MQL5\\Profiles\\Templates\\EA_Launch_Base.tpl)
  2. python3 validation/mt5_harness/gen_launcher.py \
         --base-tpl "<data>\\MQL5\\Profiles\\Templates\\EA_Launch_Base.tpl"
  3. Copy ``out/launch/*`` into ``<data>\\MQL5\\Files\\EA_Launch\\``
     (MetaTrader: File -> Open Data Folder -> MQL5 -> Files).
  4. Attach ``PortfolioLauncher`` to one chart, Algo Trading ON, press OK
     (START).  It opens + attaches all 65; re-running it skips what is
     already running.  ``EA_Launch\\launch_status.csv`` records every result.

Without ``--base-tpl`` a minimal template is synthesised (documented MT5
format, ``flags=343`` = long+short, alerts, live trading) and a warning is
printed - prefer the base template, because your terminal's own file is
authoritative for permissions.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_tester_configs as gtc  # noqa: E402  (loader for scripts/gen_additional_eas.py)

REPO = gtc.REPO
TF_MINUTES = {"M1": 1, "M5": 5, "M15": 15, "M30": 30, "H1": 60, "H4": 240, "D1": 1440}

SYNTH_FLAGS = "343"      # long+short, alerts, live trading, DLL/external imports
DEFAULT_FOLDER = "EA_Launch"


# --------------------------------------------------------------------------
# enum support: templates store enum inputs as integers, not symbol names
# --------------------------------------------------------------------------
def enum_map(header: Path, enum_name: str) -> dict[str, int]:
    src = header.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"enum\s+" + enum_name + r"\s*\{(.*?)\}", src, re.S)
    if not m:
        return {}
    out: dict[str, int] = {}
    ordinal = 0
    for item in m.group(1).split(","):
        item = re.sub(r"//.*", "", item).strip()
        if not item:
            continue
        if "=" in item:
            key, val = item.split("=", 1)
            key, val = key.strip(), val.strip()
            try:
                ordinal = int(val, 0)
            except ValueError:
                continue
        else:
            key = item
        out[key] = ordinal
        ordinal += 1
    return out


def strategy_of(ea) -> str:
    m = re.search(r'cfg\.strategyName\s*=\s*"([^"]+)"', ea.configure)
    return m.group(1) if m else ""


def template_inputs(ea, enums: dict[str, dict[str, int]]) -> list[tuple[str, str]]:
    """(name, value) pairs, enum names converted to their integer value."""
    rows = []
    for name, value in gtc.input_defaults(ea):
        for em in enums.values():
            if value in em:
                value = str(em[value])
                break
        rows.append((name, value))
    return rows


# --------------------------------------------------------------------------
# template construction
# --------------------------------------------------------------------------
def expert_prefix(base_name: str) -> str:
    """Mirror the base template's own path convention for the EA name."""
    if base_name.startswith("Experts\\") or base_name.startswith("Experts/"):
        return "Experts\\additionalEAs\\"
    if "\\" in base_name or "/" in base_name:
        return "additionalEAs\\"
    return ""


def build_from_base(base: str, ea_name: str, inputs: list[tuple[str, str]]) -> str:
    m = re.search(r"<expert>(.*?)</expert>", base, re.S | re.I)
    if not m:
        raise SystemExit("base template has no <expert> block - attach an EA to the "
                         "chart before saving it as a template")
    block = m.group(1)
    nm = re.search(r"^\s*name\s*=\s*(.+?)\s*$", block, re.M | re.I)
    prefix = expert_prefix(nm.group(1).strip()) if nm else ""
    # drop the old name line and the whole old <inputs> container
    body = re.sub(r"^\s*name\s*=.*$", "", block, flags=re.M | re.I)
    body = re.sub(r"<inputs>.*?</inputs>", "", body, flags=re.S | re.I)
    body = body.rstrip("\n")
    new_block = (f"\nname={prefix}{ea_name}\n{body.lstrip(chr(10))}\n"
                 f"<inputs>\n" + "".join(f"{k}={v}\n" for k, v in inputs) + "</inputs>\n")
    return base[:m.start()] + "<expert>" + new_block + "</expert>" + base[m.end():]


def build_synth(symbol: str, tf: str, ea_name: str, inputs: list[tuple[str, str]]) -> str:
    ind = (f"\n<inputs>\n" + "".join(f"{k}={v}\n" for k, v in inputs) + "</inputs>\n")
    return (
        "<chart>\n"
        "id=0\n"
        f"symbol={symbol}\n"
        f"period={TF_MINUTES.get(tf, 5)}\n"
        "<window>\n"
        "height=100\n"
        "fixed_height=0\n"
        "<indicator>\n"
        "name=main\n"
        "</indicator>\n"
        "</window>\n"
        "<expert>\n"
        f"name=Experts\\additionalEAs\\{ea_name}\n"
        f"flags={SYNTH_FLAGS}\n"
        "window_num=0\n"
        + ind +
        "</expert>\n"
        "</chart>\n"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-tpl", default="",
                    help="a .tpl saved from your own terminal (strongly recommended)")
    ap.add_argument("--out", default=str(REPO / "validation" / "mt5_harness" / "out" / "launch"))
    ap.add_argument("--folder", default=DEFAULT_FOLDER,
                    help="folder name under MQL5\\Files the script reads (default EA_Launch)")
    ap.add_argument("--groups", type=int, default=1,
                    help="split into N groups (one terminal per group; default 1 = all)")
    ap.add_argument("--only", default="", help="comma-separated EA name substrings")
    args = ap.parse_args()

    gen = gtc.load_generator()
    eas = list(gen.EAS)
    if args.only:
        wanted = [w.strip() for w in args.only.split(",") if w.strip()]
        eas = [e for e in eas if any(w in e.name for w in wanted)]

    base = Path(args.base_tpl).read_text(encoding="utf-8", errors="replace") if args.base_tpl else ""
    if args.base_tpl and "<expert>" not in base.lower():
        print(f"WARNING: {args.base_tpl} has no <expert> block; falling back to synth", file=sys.stderr)
        base = ""

    enums = {"ENUM_EA_LOG_LEVEL": enum_map(REPO / "MQL5_Master" / "Include" / "EACore.mqh",
                                           "ENUM_EA_LOG_LEVEL")}
    out = Path(args.out)
    (out / "templates").mkdir(parents=True, exist_ok=True)

        # 'enabled' is the post-demo switch: set 0 to skip that EA on the next START
    # (the same magic is the switch in the one-chart PortfolioEA: InpRun_<magic>)
    plan = ["group,enabled,ea,symbol,tf,template,magic,strategy,universe"]
    magics: dict[int, str] = {}
    for i, ea in enumerate(eas):
        if ea.magic in magics:
            print(f"DUPLICATE MAGIC {ea.magic}: {ea.name} / {magics[ea.magic]}", file=sys.stderr)
            return 2
        magics[ea.magic] = ea.name
        sym, tf = gtc.primary_symbol(ea), gtc.timeframe_of(ea)
        rows = template_inputs(ea, enums)
        tpl = (build_from_base(base, ea.name, rows) if base
               else build_synth(sym, tf, ea.name, rows))
        (out / "templates" / f"{ea.name}.tpl").write_text(tpl, encoding="utf-8")
        group = (i % args.groups) + 1
        universe = ";".join(gtc.symbols_of(ea))          # ';' keeps the CSV parseable
        plan.append(f"{group},1,{ea.name},{sym},{tf},{ea.name},{ea.magic},"
                    f"{strategy_of(ea)},{universe}")

    (out / "launch_plan.csv").write_text("\n".join(plan) + "\n", encoding="utf-8")

    readme = f"""QUICK START (generated by validation/mt5_harness/gen_launcher.py)
===============================================================
1. Copy this whole folder ({out.name}/) into
   <MetaTrader data folder>\\MQL5\\Files\\{args.folder}\\
   (MetaTrader: File -> Open Data Folder -> MQL5 -> Files)
2. Compile MQL5_Master/Scripts/PortfolioLauncher.mq5 (MetaEditor).
3. Make sure "Algo Trading" is ON in the terminal, then drag
   PortfolioLauncher onto any chart and press OK.
   - START creates the charts and attaches every EA from the templates.
   - launch_plan.csv column 2 is 'enabled': set it to 0 for any EA you want off
     after demo testing, then run START again (column 7 is its magic, and the
     same magic is InpRun_<magic> in the one-chart portfolio EA).
   - It is safe to run again: EAs already running are skipped.
   - STOP closes every chart that is running one of these EAs.
   - DRYRUN only reports what it would do.
4. Results are written to MQL5\\Files\\{args.folder}\\launch_status.csv.

Groups: {args.groups}.  If >1, each terminal runs the launcher with
InpGroup=<n> so the chart load is split (each EA still gets its own thread,
but memory/UI and one terminal's stability stay bounded).

The templates were {"derived from " + args.base_tpl if args.base_tpl else "SYNTHESISED (no --base-tpl): verify one attach before trusting all 65"}.
"""
    (out / "READ_ME_FIRST.txt").write_text(readme, encoding="utf-8")

    print(f"OK - {len(eas)} templates + launch_plan.csv written to {out}")
    print(f"     source: {'base template ' + args.base_tpl if args.base_tpl else 'synthesised (flags=' + SYNTH_FLAGS + ')'}")
    print(f"     groups: {args.groups} | folder in MQL5\\Files: {args.folder}")
    if not args.base_tpl:
        print("     WARNING: no --base-tpl. Save one template from your own terminal so the")
        print("              EA permissions (flags=) come from your MT5, not from a guess.")
    prefix = expert_prefix(re.search(r"^\s*name\s*=\s*(.+?)\s*$",
                                     re.search(r"<expert>(.*?)</expert>", base, re.S | re.I).group(1),
                                     re.M | re.I).group(1).strip()) if base else "Experts\\additionalEAs\\"
    print(f"     expert name convention: '{prefix}<EA>'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
