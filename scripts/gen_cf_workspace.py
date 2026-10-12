#!/usr/bin/env python3
"""Generate MT5 Profile and Chart Templates for all 47 ChartFanatics Expert Advisors.

Produces:
1. Native MT5 Profile ('ChartFanatics'):
   MQL5/Profiles/Charts/ChartFanatics/chart01.chr .. chart47.chr + order.wnd
   When selected in MT5 (File -> Profiles -> ChartFanatics), MT5 opens all 47
   charts with the corresponding EAs attached on their documented symbols/timeframes.

2. Standalone Chart Templates (.tpl):
   MQL5/Profiles/Templates/CF_<name>.tpl
   Right-click any chart -> Template -> CF_<name> to attach immediately with inputs.

3. Launch Plan for PortfolioLauncher script:
   MQL5/Files/EA_Launch/launch_plan_cf.csv
"""

import json
import os
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CF_DIR = REPO_ROOT / "chartfanatics"
MANIFEST_PATH = CF_DIR / "mql5-eas" / "manifest.json"
EAS_DIR = CF_DIR / "mql5-eas"

# MT5 Terminal data directory
APPDATA = os.environ.get("APPDATA", "")
TERMINAL_ID = "930119AA53207C8778B41171FBFFB46F"
MT5_MQL5 = Path(APPDATA) / "MetaQuotes" / "Terminal" / TERMINAL_ID / "MQL5"

TF_MAP = {
    "M1": (1, 1, 1),
    "M2": (1, 2, 2),
    "M3": (1, 3, 3),
    "M5": (1, 5, 5),
    "M15": (1, 15, 15),
    "M30": (1, 30, 30),
    "H1": (2, 1, 60),
    "H4": (2, 4, 240),
    "D1": (3, 1, 1440),
}


def parse_timeframe(tf_str: str) -> tuple[int, int, int]:
    clean = tf_str.split()[0].split("/")[0].strip().upper()
    return TF_MAP.get(clean, (1, 5, 5))  # Default M5


def extract_inputs_and_symbols(ea_path: Path) -> tuple[str, list[tuple[str, str]]]:
    src = ea_path.read_text(encoding="utf-8", errors="replace")
    
    # Extract universe
    sym_match = re.search(r'InpSymbolsToTrade\s*=\s*"([^"]+)"', src)
    syms = sym_match.group(1) if sym_match else "EURUSD"
    primary_sym = [s.strip() for s in syms.split(",") if s.strip()][0]

    # Extract all input definitions
    inputs = []
    input_matches = re.finditer(r'input\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)\s*=\s*([^;]+);', src)
    for m in input_matches:
        var_name = m.group(2).strip()
        var_val = m.group(3).strip()
        # Clean value quotes if string
        if var_val.startswith('"') and var_val.endswith('"'):
            var_val = var_val[1:-1]
        inputs.append((var_name, var_val))

    return primary_sym, inputs


def build_chart_chr(chart_id: int, symbol: str, tf_type: int, tf_size: int, ea_name: str, inputs: list[tuple[str, str]]) -> str:
    inputs_block = "\n".join(f"{k}={v}" for k, v in inputs)
    return (
        f"<chart>\n"
        f"id={chart_id}\n"
        f"symbol={symbol}\n"
        f"description={symbol}\n"
        f"period_type={tf_type}\n"
        f"period_size={tf_size}\n"
        f"digits=5\n"
        f"tick_size=0.000000\n"
        f"scale=4\n"
        f"mode=1\n"
        f"fore=0\n"
        f"grid=1\n"
        f"volume=0\n"
        f"scroll=1\n"
        f"shift=1\n"
        f"ticker=1\n"
        f"bidline=1\n"
        f"askline=0\n"
        f"lastline=0\n"
        f"days=1\n"
        f"window_left=0\n"
        f"window_top=0\n"
        f"window_right=800\n"
        f"window_bottom=400\n"
        f"window_type=1\n"
        f"background_color=0\n"
        f"foreground_color=16777215\n"
        f"barup_color=65280\n"
        f"bardown_color=65280\n"
        f"bullcandle_color=0\n"
        f"bearcandle_color=16777215\n"
        f"chartline_color=65280\n"
        f"volumes_color=3329330\n"
        f"grid_color=10061943\n"
        f"bidline_color=10061943\n"
        f"askline_color=255\n"
        f"lastline_color=49152\n"
        f"stops_color=255\n"
        f"windows_total=1\n"
        f"<expert>\n"
        f"name={ea_name.replace('.mq5', '')}\n"
        f"path=Experts\\chartfanatics\\{ea_name.replace('.mq5', '.ex5')}\n"
        f"expertmode=1\n"
        f"<inputs>\n"
        f"{inputs_block}\n"
        f"</inputs>\n"
        f"</expert>\n"
        f"<window>\n"
        f"height=100\n"
        f"fixed_height=0\n"
        f"<indicator>\n"
        f"name=main\n"
        f"</indicator>\n"
        f"</window>\n"
        f"</chart>\n"
    )


def build_template_tpl(symbol: str, tf_type: int, tf_size: int, ea_name: str, inputs: list[tuple[str, str]]) -> str:
    inputs_block = "\n".join(f"{k}={v}" for k, v in inputs)
    return (
        f"<chart>\n"
        f"id=0\n"
        f"symbol={symbol}\n"
        f"period_type={tf_type}\n"
        f"period_size={tf_size}\n"
        f"scale=4\n"
        f"mode=1\n"
        f"grid=1\n"
        f"volume=0\n"
        f"scroll=1\n"
        f"shift=1\n"
        f"bidline=1\n"
        f"background_color=0\n"
        f"foreground_color=16777215\n"
        f"barup_color=65280\n"
        f"bardown_color=65280\n"
        f"bullcandle_color=0\n"
        f"bearcandle_color=16777215\n"
        f"<window>\n"
        f"height=100\n"
        f"fixed_height=0\n"
        f"<indicator>\n"
        f"name=main\n"
        f"</indicator>\n"
        f"</window>\n"
        f"<expert>\n"
        f"name=Experts\\chartfanatics\\{ea_name.replace('.mq5', '')}\n"
        f"flags=343\n"
        f"window_num=0\n"
        f"<inputs>\n"
        f"{inputs_block}\n"
        f"</inputs>\n"
        f"</expert>\n"
        f"</chart>\n"
    )


def main():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)["eas"]

    print(f"Generating MT5 workspace for {len(manifest)} ChartFanatics EAs...")

    # 1. Profile directory
    profile_dir = MT5_MQL5 / "Profiles" / "Charts" / "ChartFanatics"
    profile_dir.mkdir(parents=True, exist_ok=True)

    # 2. Template directory in terminal and repo
    terminal_tpl_dir = MT5_MQL5 / "Profiles" / "Templates"
    terminal_tpl_dir.mkdir(parents=True, exist_ok=True)
    repo_tpl_dir = CF_DIR / "templates"
    repo_tpl_dir.mkdir(parents=True, exist_ok=True)

    # 3. EA_Launch directory
    ea_launch_dir = MT5_MQL5 / "Files" / "EA_Launch"
    ea_launch_dir.mkdir(parents=True, exist_ok=True)
    launch_tpl_dir = ea_launch_dir / "templates"
    launch_tpl_dir.mkdir(parents=True, exist_ok=True)

    order_wnd_entries = []
    launch_plan_rows = ["group,enabled,ea,symbol,tfMinutes,tfLabel,templateName,universe"]

    base_chart_id = 140000000000000000

    for idx, entry in enumerate(manifest, 1):
        ea_name = entry["ea"]
        tf_str = entry["timeframe"]
        ea_path = EAS_DIR / ea_name
        
        primary_sym, inputs = extract_inputs_and_symbols(ea_path)
        tf_type, tf_size, tf_minutes = parse_timeframe(tf_str)
        chart_id = base_chart_id + idx

        # Generate chart file chartXX.chr
        chr_filename = f"chart{idx:02d}.chr"
        chr_content = build_chart_chr(chart_id, primary_sym, tf_type, tf_size, ea_name, inputs)
        chr_path = profile_dir / chr_filename
        chr_path.write_text(chr_content, encoding="utf-16le")
        order_wnd_entries.append(chr_filename)

        # Generate template .tpl
        tpl_name = f"CF_{ea_name.replace('.mq5', '')}"
        tpl_content = build_template_tpl(primary_sym, tf_type, tf_size, ea_name, inputs)

        # Write to MT5 Templates
        (terminal_tpl_dir / f"{tpl_name}.tpl").write_text(tpl_content, encoding="utf-16le")
        # Write to repo templates
        (repo_tpl_dir / f"{tpl_name}.tpl").write_text(tpl_content, encoding="utf-8")
        # Write to EA_Launch templates
        (launch_tpl_dir / f"{tpl_name}.tpl").write_text(tpl_content, encoding="utf-16le")

        # Row for launch_plan_cf.csv
        universe = ";".join(dict(inputs).get("InpSymbolsToTrade", primary_sym).split(","))
        launch_plan_rows.append(
            f"1,1,{ea_name.replace('.mq5', '')},{primary_sym},{tf_minutes},{tf_str.split()[0]},{tpl_name},{universe}"
        )

    # Write order.wnd in profile directory
    order_wnd_content = "\n".join(order_wnd_entries) + "\n"
    (profile_dir / "order.wnd").write_text(order_wnd_content, encoding="utf-16le")

    # Write launch_plan.csv for PortfolioLauncher
    (ea_launch_dir / "launch_plan.csv").write_text("\n".join(launch_plan_rows) + "\n", encoding="utf-8")

    print(f"[OK] Created MT5 Profile 'ChartFanatics' with {len(manifest)} charts at:")
    print(f"     {profile_dir}")
    print(f"[OK] Created {len(manifest)} chart templates in:")
    print(f"     {terminal_tpl_dir} (CF_*.tpl)")
    print(f"[OK] Created PortfolioLauncher launch plan at:")
    print(f"     {ea_launch_dir / 'launch_plan.csv'}")


if __name__ == "__main__":
    main()
