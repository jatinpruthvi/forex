# history-data tooling

Local helpers used to build the M1/M5 price history that feeds backtesting and
validation. Two upstream projects are used as checkouts and extended with local
scripts in this folder.

## Layout

### `dukascopy-node/`

Checkout of [Leo4815162342/dukascopy-node](https://github.com/Leo4815162342/dukascopy-node)
**v1.50.0**, upstream commit `519a790`. The local scripts live at its root and
`require('./dist/index.js')`, i.e. they run inside that checkout:

| Script | Purpose |
| --- | --- |
| `download-m5.js` | Downloads 5 years of M5 bid candles as CSV for one instrument (`node download-m5.js <instrument>`). |
| `run-all-m5.js` | Sequentially runs the M5 download for all pairs; resumable, skips pairs whose output exists. |
| `run-chunked-m5.js` | Rate-limit-aware M5 downloader for the 11 pairs: 6-month chunks, multi-pass, per-pair pauses/cool-downs, then assembles the final CSV in `m5-data/`. Re-runnable. |
| `assemble-4y.js` | Assembles the final 4-year M5 CSVs: legacy segment (2022-09-11 -> mirror start) + mirror segment (-> live). |
| `assemble-m1.js` | Same assembly for the 2-year M1 CSVs (2024-09-11 -> live). |
| `fill-gap-histdata.js` | Fills 2022-09-11 -> mirror start from histdata.com M1 ASCII zips (EST, fixed UTC-5), aggregates M1 -> M5 into `{pair}-m5-legacy.csv`. |
| `fill-gap-histdata-m1.js` | Same gap fill at M1 granularity; histdata stamps are New York local time *with* DST, so conversion is DST-aware. |
| `fill-legacy-bi5.js` | Fills the same gap from Dukascopy's legacy `.bi5` M1 candle feed (LZMA FORMAT_ALONE, zero-based month). |
| `fetch-fsb-all.js` | Downloads all 11 pairs of M5 bars from the ForexSB Dukascopy mirror and decodes the 28-byte binary records into dukascopy-node-style CSVs. |
| `fetch-fsb-m1.js` | Same as above for M1 bars. |
| `validate-m5.js` | Validation suite for the 4-year M5 CSVs: structure, timestamp grid/uniqueness, OHLC logic, weekend bars, gap histogram, flat-bar runs. |
| `validate-m1.js` | Validation suite for the 2-year M1 CSVs (New York weekend cut-offs). |
| `trim-dst-hours.js` | Removes the 4 anomalous Sunday 20:00-20:59 UTC buckets (DST-transition artifacts) from the final 4-year CSVs, in place. |
| `decode-fsb.js` | Prototype decoder for ForexSB binary records (28 bytes, uint32 LE, prices x1e5). |
| `decode-bi5-test.js` | Prototype decoder for a single Dukascopy legacy `.bi5` M1 candle day file, validated against the mirror. |
| `histdata-dl.py` | Thin wrapper around `histdata.download_hist_data` (M1 ASCII). |

### `FXCM-Forex-Data-Downloader/`

Checkout of [grananqvist/FXCM-Forex-Data-Downloader](https://github.com/grananqvist/FXCM-Forex-Data-Downloader),
upstream commit `bef9405` (`main.py`, an `fxcmpy`-based downloader kept as an
alternative data source).

## Not versioned

`.gitignore` in this folder excludes everything that is large or regenerable:
`node_modules/`, `dist/`, upstream `src/`/`examples/` trees, `*.gz`, `*.bin`,
`*.bi5`, `fsb-raw/`, `bi5-cache/`, run logs, and the generated `m1-data/`,
`m5-data/` CSV output.

## Restoring the full working checkouts

Each vendored folder still contains its original clone metadata, renamed to
`.git-upstream.bak` so that the parent repository can track the files inside it.
Restore a checkout to pull/re-install/build:

```powershell
cd scripts\history-data\dukascopy-node
Rename-Item .git-upstream.bak .git
git pull                 # optional: newer upstream version
pnpm install             # restores node_modules/
pnpm build               # regenerates dist/ - the local scripts require ./dist/index.js
```

The same rename applies to `FXCM-Forex-Data-Downloader\.git-upstream.bak`
(restore, then `pip install fxcmpy tqdm`).
