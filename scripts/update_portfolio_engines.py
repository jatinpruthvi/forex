import json
import os
from pathlib import Path

def update_engines():
    appdata = os.environ.get("APPDATA", "")
    term_engines = Path(appdata) / "MetaQuotes" / "Terminal" / "930119AA53207C8778B41171FBFFB46F" / "MQL5" / "Files" / "PortfolioEA" / "engines.csv"
    
    if not term_engines.exists():
        term_engines.parent.mkdir(parents=True, exist_ok=True)
        existing_lines = ["magic,tag,ea,strategy,symbols,timeframe,risk_pct,switch,order_policy,source_doc"]
    else:
        existing_lines = term_engines.read_text(encoding="utf-8").splitlines()

    existing_magics = set()
    for l in existing_lines[1:]:
        if l.strip():
            existing_magics.add(int(l.split(",")[0]))

    cf_manifest = json.loads(Path("chartfanatics/mql5-eas/manifest.json").read_text(encoding="utf-8"))["eas"]

    new_lines = []
    for item in cf_manifest:
        magic = item["magic"]
        if magic in existing_magics:
            continue
        tag = f"P{magic}|"
        ea = item["ea"].replace(".mq5", "")
        strat = item["strategy"].replace(",", ";")
        tf = item["timeframe"]
        risk = "0.01 lot"
        switch = f"InpRun_{magic}"
        policy = "one per symbol"
        doc = item["source"]
        
        ea_src = Path("chartfanatics/mql5-eas", item["ea"]).read_text(encoding="utf-8")
        syms = "EURUSD"
        for l in ea_src.splitlines():
            if "InpSymbolsToTrade" in l and "=" in l:
                syms = l.split("=")[1].split(";")[0].strip().strip('"').replace(",", ";")
        
        line = f"{magic},{tag},{ea},{strat},{syms},{tf},{risk},{switch},{policy},{doc}"
        new_lines.append(line)

    print(f"Existing engines: {len(existing_magics)}")
    print(f"Adding CF engines: {len(new_lines)}")
    all_lines = existing_lines + new_lines
    term_engines.write_text("\n".join(all_lines), encoding="utf-8")
    print(f"Total engines in terminal engines.csv: {len(all_lines)-1}")

    repo_engines = Path("portfolio-EA/build/engines.csv")
    if repo_engines.parent.exists():
        repo_engines.write_text("\n".join(all_lines), encoding="utf-8")
        print("Updated repo build/engines.csv")

if __name__ == "__main__":
    update_engines()
