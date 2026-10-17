#!/usr/bin/env python3
"""Download free public macro inputs for research (stdlib only): FRED series (no key needed via fredgraph.csv) and CFTC
Commitments-of-Traders financial-futures history. Output: ./out/macro/*. Run on a GitHub runner (the research sandbox cannot reach these hosts)."""
import io
import os
import sys
import time
import urllib.request
import zipfile

OUT = os.path.join(os.getcwd(), "out", "macro")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (research-data-fetch)"}
FRED = {
    # policy / short rates, monthly (OECD immediate rates) + US daily
    "FEDFUNDS": "USD fed funds (monthly)", "IRSTCI01EZM156N": "EUR immediate rate (monthly)", "IRSTCI01GBM156N": "GBP (monthly)",
    "IRSTCI01JPM156N": "JPY (monthly)", "IRSTCI01AUM156N": "AUD (monthly)", "IRSTCI01NZM156N": "NZD (monthly)",
    "IRSTCI01CAM156N": "CAD (monthly)", "IRSTCI01CHM156N": "CHF (monthly)", "ECBDFR": "ECB deposit facility rate (daily)",
    "DFF": "US effective fed funds (daily)",
    # risk / dollar / curve, daily
    "DTWEXBGS": "Broad trade-weighted USD index (daily)", "VIXCLS": "VIX (daily)", "DGS2": "US 2y (daily)", "DGS10": "US 10y (daily)",
    "GOLDPMGBD228NLBM": "LBMA gold PM (daily, may be discontinued)",
}


def get(url, tries=4):
    for k in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            print(f"  retry {k + 1} {url}: {e}", file=sys.stderr)
            time.sleep(3 * (k + 1))
    return None


log = []
for sid, desc in FRED.items():
    b = get(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={sid}&cosd=2010-01-01")
    if b and len(b) > 100:
        open(os.path.join(OUT, f"fred_{sid}.csv"), "wb").write(b)
        log.append(f"ok   FRED {sid} {len(b)} bytes  {desc}")
    else:
        log.append(f"FAIL FRED {sid}  {desc}")
for y in range(2015, 2027):
    for kind in ("fut_fin_txt", "com_disagg_txt"):
        b = get(f"https://www.cftc.gov/files/dea/history/{kind}_{y}.zip")
        if b and b[:2] == b"PK":
            open(os.path.join(OUT, f"cot_{kind}_{y}.zip"), "wb").write(b)
            log.append(f"ok   COT {kind} {y} {len(b)} bytes")
        else:
            log.append(f"FAIL COT {kind} {y}")
open(os.path.join(OUT, "MACRO_LOG.txt"), "w").write("\n".join(log) + "\n")
print("\n".join(log))
