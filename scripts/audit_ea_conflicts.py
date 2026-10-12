import json
import re
from pathlib import Path

def analyze_eas():
    manifest_file = Path("chartfanatics/mql5-eas/manifest.json")
    with open(manifest_file, "r", encoding="utf-8") as f:
        data = json.load(f)["eas"]

    print(f"Total EAs to analyze: {len(data)}")

    magics = set()
    ea_names = set()
    symbols_used = {}
    timeframes_used = {}
    entry_types = {"market": 0, "limit": 0}

    for item in data:
        magic = item["magic"]
        ea_file = Path("chartfanatics/mql5-eas", item["ea"])
        content = ea_file.read_text(encoding="utf-8", errors="replace")

        # Magic uniqueness
        if magic in magics:
            print(f"CONFLICT: Duplicate magic {magic}")
        magics.add(magic)

        # Symbols
        m_sym = re.search(r'input\s+string\s+InpSymbolsToTrade\s*=\s*"([^"]+)"', content)
        sym_str = m_sym.group(1) if m_sym else "N/A"
        for s in sym_str.split(","):
            s = s.strip()
            symbols_used.setdefault(s, []).append(magic)

        # Timeframe
        tf = item["timeframe"]
        timeframes_used.setdefault(tf, []).append(magic)

        # Entry mechanism
        if "useLimitEntry = true" in content or "OpenLimit" in content or "isLimit = true" in content:
            entry_types["limit"] += 1
        else:
            entry_types["market"] += 1

    print("\n--- MAGIC NUMBER AUDIT ---")
    print(f"Unique magics count: {len(magics)} (Min: {min(magics)}, Max: {max(magics)})")

    print("\n--- TIMEFRAME DISTRIBUTION ---")
    for tf, m_list in sorted(timeframes_used.items()):
        print(f"Timeframe {tf:5}: {len(m_list)} EAs")

    print("\n--- SYMBOL OVERLAP AUDIT ---")
    for sym, m_list in sorted(symbols_used.items(), key=lambda x: len(x[1]), reverse=True)[:10]:
        print(f"Symbol '{sym}': traded by {len(m_list)} strategies (Magics: {m_list[:5]}...)")

if __name__ == "__main__":
    analyze_eas()
