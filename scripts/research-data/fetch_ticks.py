#!/usr/bin/env python3
"""Download histdata.com tick quotes (bid and ask) for some pair-months and reduce them to 1-minute bid/ask OHLC + spread statistics.
Needs: pip install histdata==1.1 pandas. Output: ./out/ticks/<pair>-<yyyy>-<mm>-1min.csv.gz, column `min` = epoch SECONDS of the feed clock.
The timestamps are the feed's own clock as printed by histdata (naive): UTC-5 in winter / UTC-4 in summer, switching on the EUROPEAN DST dates (see tools/tick_lab.py feed_to_utc_ms).
Usage: fetch_ticks.py --pairs eurusd,gbpusd --months 2025-09,2025-10"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

import pandas as pd

ap = argparse.ArgumentParser()
ap.add_argument("--pairs", required=True)
ap.add_argument("--months", required=True)
a = ap.parse_args()
OUT = os.path.join(os.getcwd(), "out", "ticks")
os.makedirs(OUT, exist_ok=True)
log = []
for pair in a.pairs.split(","):
    for ym in a.months.split(","):
        y, m = ym.split("-")
        dest = os.path.join(OUT, f"{pair}-{y}-{m}-1min.csv.gz")
        if os.path.exists(dest):
            continue
        tmp = tempfile.mkdtemp()
        try:
            code = ("from histdata import download_hist_data as dl; "
                    f"dl(year='{y}', month='{int(m)}', pair='{pair}', time_frame='T', platform='ASCII', output_directory={tmp!r}, verbose=False)")
            r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=1500)
            zips = glob.glob(os.path.join(tmp, "*.zip"))
            if not zips:
                log.append(f"FAIL {pair} {ym}: no zip ({(r.stderr or r.stdout)[-200:].strip()})")
                continue
            with zipfile.ZipFile(zips[0]) as z:
                name = [n for n in z.namelist() if n.lower().endswith(".csv")][0]
                z.extract(name, tmp)
            df = pd.read_csv(os.path.join(tmp, name), header=None, names=["t", "bid", "ask", "v"], usecols=[0, 1, 2], dtype={"t": str})
            t = pd.to_datetime(df["t"], format="%Y%m%d %H%M%S%f")
            # epoch SECONDS of the feed clock (naive). Explicit unit: pandas 3 would otherwise give us microseconds and the old // 10**6 was seconds by accident.
            df["min"] = t.dt.floor("min").astype("datetime64[s]").astype("int64")
            df["spr"] = df["ask"] - df["bid"]
            g = df.groupby("min", sort=True)
            res = pd.DataFrame({"bid_o": g["bid"].first(), "bid_h": g["bid"].max(), "bid_l": g["bid"].min(), "bid_c": g["bid"].last(),
                                "ask_o": g["ask"].first(), "ask_h": g["ask"].max(), "ask_l": g["ask"].min(), "ask_c": g["ask"].last(),
                                "spr_mean": g["spr"].mean(), "spr_max": g["spr"].max(), "spr_min": g["spr"].min(), "n": g["bid"].size()})
            res.to_csv(dest, compression="gzip", float_format="%.6f")
            log.append(f"ok   {pair} {ym}: {len(df)} ticks -> {len(res)} minutes")
        except Exception as e:  # noqa: BLE001
            log.append(f"FAIL {pair} {ym}: {e!r}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        print(log[-1], flush=True)
open(os.path.join(OUT, f"TICKS_LOG_{a.pairs.replace(',', '_')}.txt"), "a").write("\n".join(log) + "\n")
