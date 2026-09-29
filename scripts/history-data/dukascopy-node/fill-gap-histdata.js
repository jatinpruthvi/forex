/* Fill the gap 2016-09-11 -> per-pair mirror start using histdata.com m1 ASCII zips.
   - Downloads 2016..2025 M1 zips per pair (cached)
   - histdata stamps switch to/from summer time on the EU DST calendar (last Sun Mar /
     last Sun Oct), NOT the US calendar - empirically verified against the official
     Dukascopy feed (see fill-gap-histdata-m1.js): UTC = stamp +4h in EU-summer, +5h otherwise
   - Sunday bars before the 17:00 NY open are dropped (histdata opens ~1h early on
     EU DST-change Sundays; phantom bars absent from the official feed)
   - Aggregate m1 -> m5, format identical to mirror CSVs (volume=0 in this segment)
   - Writes {pair}-m5-legacy.csv per pair for later concatenation with the mirror file. */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const BASE = path.join(__dirname, '..');
const OUT_DIR = path.join(BASE, 'm5-data');
const SEG_DIR = path.join(OUT_DIR, 'intermediates'); // per-segment files
const CACHE_DIR = path.join(BASE, 'histdata-cache');
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.mkdirSync(SEG_DIR, { recursive: true });
fs.mkdirSync(CACHE_DIR, { recursive: true });

const FILL_START = Date.UTC(2016, 8, 11); // 2016-09-11 00:00 UTC -> 10-year window
const PREC = {
  eurusd: 5, usdjpy: 3, gbpusd: 5, xauusd: 3, eurgbp: 5, eurjpy: 3,
  audusd: 5, usdcad: 5, nzdusd: 5, usdchf: 5, gbpjpy: 3
};
const YEARS = ['2016', '2017', '2018', '2019', '2020', '2021', '2022', '2023', '2024', '2025'];

function runPython(args) {
  execFileSync('python', [path.join(__dirname, 'histdata-dl.py'), ...args], { stdio: 'inherit' });
}

function parseAndAggregate(zipPath, mirrorStart, prec) {
  const { execSync } = require('child_process');
  const csvName = path.basename(zipPath, '.zip') + '.csv';
  const csvPath = path.join(CACHE_DIR, csvName);
  if (!fs.existsSync(csvPath)) {
    execSync(`unzip -o -q "${zipPath}" -d "${CACHE_DIR}"`);
  }
  const text = fs.readFileSync(csvPath, 'utf8');
  const buckets = new Map();

  function isEDT(y, mo, d) {
    const lastSun = m => {
      const d0 = new Date(Date.UTC(y, m + 1, 0)); // last day of month m (0-based)
      return d0.getUTCDate() - d0.getUTCDay();
    };
    const cur = new Date(Date.UTC(y, mo - 1, d)).getUTCDate();
    if (mo === 3) return cur >= lastSun(2);
    if (mo === 10) return cur < lastSun(9);
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

    // Drop Sunday bars before the NY open (17:00 NY local): histdata's clock
    // opens ~1h early on EU DST-change Sundays (phantom bars absent from the
    // official feed). Stamps are NY local, so the check is on the raw hour.
    if (new Date(Date.UTC(y, mo - 1, d)).getUTCDay() === 0 && h < 17) continue;

    const o = +fields[1], hh = +fields[2], l = +fields[3], c = +fields[4];
    const b = Math.floor(tsUtc / 300000) * 300000;
    if (!buckets.has(b)) buckets.set(b, [o, hh, l, c]);
    else {
      const a = buckets.get(b);
      a[1] = Math.max(a[1], hh);
      a[2] = Math.min(a[2], l);
      a[3] = c;
    }
  }

  return [...buckets.entries()]
    .sort((x, y) => x[0] - y[0])
    .map(
      ([b, a]) =>
        `${b},${a[0].toFixed(prec)},${a[1].toFixed(prec)},${a[2].toFixed(prec)},${a[3].toFixed(prec)},0`
    );
}

(async () => {
  console.log(`[${new Date().toISOString()}] gap fill via histdata.com for ${Object.keys(PREC).length} pairs`);
  for (const pair of Object.keys(PREC)) {
    try {
      const mirrorFile = path.join(SEG_DIR, `${pair}-m5-fsb.csv`);
      const mirrorStart = +fs.readFileSync(mirrorFile, 'utf8').split('\n')[1].split(',')[0];

      const allLines = [];
      for (const year of YEARS) {
        const zipPath = path.join(CACHE_DIR, `DAT_ASCII_${pair.toUpperCase()}_M1_${year}.zip`);
        if (!fs.existsSync(zipPath)) {
          runPython([year, pair.toUpperCase(), zipPath]);
        }
        // loop-push: spread-push of ~100k lines overflows the call stack
        for (const l of parseAndAggregate(zipPath, mirrorStart, PREC[pair])) allLines.push(l);
      }

      const outFile = path.join(SEG_DIR, `${pair}-m5-legacy.csv`);
      fs.writeFileSync(outFile, 'timestamp,open,high,low,close,volume\n' + allLines.join('\n') + '\n');
      const first = allLines[0]?.split(',')[0], last = allLines[allLines.length - 1]?.split(',')[0];
      console.log(
        `[${new Date().toISOString()}] OK ${pair}: ${allLines.length} m5 bars, ${first ? new Date(+first).toISOString() : '-'} -> ${last ? new Date(+last).toISOString() : '-'}`
      );
    } catch (e) {
      console.error(`[${new Date().toISOString()}] FAIL ${pair}: ${e.message}`);
    }
  }
  console.log(`[${new Date().toISOString()}] ALL_DONE`);
})();
