/* Fill the gap 2024-09-11 -> per-pair m1 mirror start using histdata.com m1 ASCII zips.
   - Uses cached 2024 M1 zips, downloads 2025 (yearly) and 2026 (monthly Jan-Mar)
   - histdata stamps are New York local time WITH DST -> DST-aware conversion to UTC
   - Keeps M1 granularity (no aggregation), format identical to mirror CSVs (volume=0)
   - Writes {pair}-m1-legacy.csv per pair for later concatenation with the mirror file. */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const BASE = path.join(__dirname, '..');
const OUT_DIR = path.join(BASE, 'm1-data');
const SEG_DIR = path.join(OUT_DIR, 'intermediates'); // per-segment files (histdata segment only)
const CACHE_DIR = path.join(BASE, 'histdata-cache');
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.mkdirSync(SEG_DIR, { recursive: true });

const FILL_START = Date.UTC(2024, 8, 11);
const PREC = {
  eurusd: 5, usdjpy: 3, gbpusd: 5, xauusd: 3, eurgbp: 5, eurjpy: 3,
  audusd: 5, usdcad: 5, nzdusd: 5, usdchf: 5, gbpjpy: 3
};
// 2024 yearly zip (cached from m5 work) + 2025 yearly + 2026 monthly (Jan-Mar)
const SOURCES = ['2024', '2025', '2026-01', '2026-02', '2026-03'];

function runPython(args) {
  execFileSync('python', [path.join(__dirname, 'histdata-dl.py'), ...args], { stdio: 'inherit' });
}

function zipPathFor(pair, src) {
  const [y, m] = src.split('-');
  const ym = m ? y + m : y;
  return path.join(CACHE_DIR, `DAT_ASCII_${pair.toUpperCase()}_M1_${ym}.zip`);
}

function parseLines(zipPath, mirrorStart, prec) {
  const { execSync } = require('child_process');
  const csvName = path.basename(zipPath, '.zip') + '.csv';
  const csvPath = path.join(CACHE_DIR, csvName);
  if (!fs.existsSync(csvPath)) {
    execSync(`unzip -o -q "${zipPath}" -d "${CACHE_DIR}"`);
  }
  const text = fs.readFileSync(csvPath, 'utf8');
  const out = [];

  // histdata stamps switch to/from summer time on the EU DST calendar (last Sun Mar / last Sun Oct),
  // NOT the US calendar — empirically verified: bars in the US-only DST windows (Mar 9-30 2025,
  // Oct 26-Nov 2 2025) match the official Dukascopy feed only with the EU-boundary offset.
  // UTC = stamp + 4h inside EU-summer, + 5h otherwise.
  function isEDT(y, mo, d) {
    const lastSun = (y, m) => {
      const d0 = new Date(Date.UTC(y, m + 1, 0)); // last day of month m (0-based)
      return d0.getUTCDate() - d0.getUTCDay();
    };
    const cur = new Date(Date.UTC(y, mo - 1, d)).getUTCDate();
    if (mo === 3) return cur >= lastSun(y, 2);
    if (mo === 10) return cur < lastSun(y, 9);
    return mo > 3 && mo < 10;
  }

  for (const line of text.split('\n')) {
    if (!line || line.length < 20) continue;
    const [datePart, rest] = line.split(' ');
    const fields = rest.split(';');
    const y = +datePart.slice(0, 4), mo = +datePart.slice(4, 6), d = +datePart.slice(6, 8);
    const h = +fields[0].slice(0, 2), mi = +fields[0].slice(2, 4), s = +fields[0].slice(4, 6);
    const offsetH = isEDT(y, mo, d) ? 4 : 5;
    const tsUtc = Date.UTC(y, mo - 1, d, h + offsetH, mi, s);
    if (tsUtc < FILL_START || tsUtc >= mirrorStart) continue;

    // Drop Sunday bars before the NY open (17:00 NY local): histdata's clock opens
    // ~1h early on EU DST-change Sundays (phantom bars absent from the official feed).
    if (new Date(Date.UTC(y, mo - 1, d)).getUTCDay() === 0 && h < 17) continue;

    const o = +fields[1], hh = +fields[2], l = +fields[3], c = +fields[4];
    out.push(`${tsUtc},${o.toFixed(prec)},${hh.toFixed(prec)},${l.toFixed(prec)},${c.toFixed(prec)},0`);
  }
  return out;
}

(async () => {
  console.log(`[${new Date().toISOString()}] m1 gap fill via histdata.com for ${Object.keys(PREC).length} pairs`);
  for (const pair of Object.keys(PREC)) {
    try {
      const mirrorFile = path.join(SEG_DIR, `${pair}-m1-fsb.csv`);
      const mirrorStart = +fs.readFileSync(mirrorFile, 'utf8').split('\n')[1].split(',')[0];

      const allLines = [];
      for (const src of SOURCES) {
        const zipPath = zipPathFor(pair, src);
        if (!fs.existsSync(zipPath)) {
          const [y, m] = src.split('-');
          runPython([y, pair.toUpperCase(), zipPath, ...(m ? [m] : [])]);
        }
        // spread-push of ~370k lines overflows the call stack; push in a loop instead
        for (const l of parseLines(zipPath, mirrorStart, PREC[pair])) allLines.push(l);
      }
      allLines.sort((a, b) => +a.split(',')[0] - +b.split(',')[0]);

      // histdata's yearly zips repeat a stretch of ~60 identical minutes on EU DST-change
      // Sundays (verified 2024-10-27 & 2025-10-26): collapse to one row per timestamp.
      const deduped = [];
      let lastTs = -1;
      for (const l of allLines) {
        const ts = +l.split(',')[0];
        if (ts === lastTs) continue;
        deduped.push(l);
        lastTs = ts;
      }

      const outFile = path.join(SEG_DIR, `${pair}-m1-legacy.csv`);
      fs.writeFileSync(outFile, 'timestamp,open,high,low,close,volume\n' + deduped.join('\n') + '\n');
      const first = deduped[0]?.split(',')[0], last = deduped[deduped.length - 1]?.split(',')[0];
      console.log(
        `[${new Date().toISOString()}] OK ${pair}: ${deduped.length} m1 bars (${allLines.length - deduped.length} dups removed), ${first ? new Date(+first).toISOString() : '-'} -> ${last ? new Date(+last).toISOString() : '-'}`
      );
    } catch (e) {
      console.error(`[${new Date().toISOString()}] FAIL ${pair}: ${e.message}`);
    }
  }
  console.log(`[${new Date().toISOString()}] ALL_DONE`);
})();