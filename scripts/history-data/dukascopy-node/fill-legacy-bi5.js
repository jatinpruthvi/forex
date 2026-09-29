/* Fill the 2022-09-11 -> mirror-start gap using Dukascopy's legacy .bi5 m1 candle feed.
   Validated: O/H/L/C exact match vs mirror, volumes sum correctly (345.06 ~ 345).
   Output: one {pair}-m5-legacy.csv per pair in m5-data/intermediates/, ready to prepend to the mirror CSV.
   Format: >iiiiif records, prices x pip scale, LZMA (FORMAT_ALONE), month is zero-based. */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const zlib = require('zlib');

const BASE = path.join(__dirname, '..');
const OUT_DIR = path.join(BASE, 'm5-data');
const SEG_DIR = path.join(OUT_DIR, 'intermediates');
const CACHE_DIR = path.join(__dirname, 'bi5-cache');
const PYTHON = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
const FILL_START = Date.UTC(2022, 8, 11); // 2022-09-11 00:00 UTC
const HTTP = 'https://datafeed.dukascopy.com/datafeed';

const PAIRS = {
  eurusd: { code: 'EURUSD', pip: 1e5, prec: 5 },
  usdjpy: { code: 'USDJPY', pip: 1e3, prec: 3 },
  gbpusd: { code: 'GBPUSD', pip: 1e5, prec: 5 },
  xauusd: { code: 'XAUUSD', pip: 1e3, prec: 3 },
  eurgbp: { code: 'EURGBP', pip: 1e5, prec: 5 },
  eurjpy: { code: 'EURJPY', pip: 1e3, prec: 3 },
  audusd: { code: 'AUDUSD', pip: 1e5, prec: 5 },
  usdcad: { code: 'USDCAD', pip: 1e5, prec: 5 },
  nzdusd: { code: 'NZDUSD', pip: 1e5, prec: 5 },
  usdchf: { code: 'USDCHF', pip: 1e5, prec: 5 },
  gbpjpy: { code: 'GBPJPY', pip: 1e3, prec: 3 }
};

fs.mkdirSync(CACHE_DIR, { recursive: true });
fs.mkdirSync(SEG_DIR, { recursive: true });

function pyLzmaDecompress(srcB64) {
  const script =
    "import sys,lzma;d=sys.stdin.buffer.read();sys.stdout.buffer.write(lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(d))";
  return execFileSync(PYTHON, ['-c', script], { input: srcB64, maxBuffer: 64 * 1024 * 1024 });
}

async function fetchUrl(url) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url);
      if (res.status === 200) return Buffer.from(await res.arrayBuffer());
      if (res.status === 404) return null;
      throw new Error(`HTTP ${res.status}`);
    } catch (e) {
      if (attempt === 3) throw e;
      await new Promise(r => setTimeout(r, 2000 * attempt));
    }
  }
}

function decodeDay(buf, dayStartMs, pip) {
  const raw = pyLzmaDecompress(buf);
  const rows = [];
  for (let o = 0; o + 24 <= raw.length; o += 24) {
    const dt = raw.readInt32BE(o);
    const open = raw.readInt32BE(o + 4) / pip;
    const close = raw.readInt32BE(o + 8) / pip;
    const low = raw.readInt32BE(o + 12) / pip;
    const high = raw.readInt32BE(o + 16) / pip;
    const vol = raw.readFloatBE(o + 20);
    rows.push([dayStartMs + dt * 1000, open, high, low, close, vol]);
  }
  return rows;
}

function aggregateM5(m1) {
  const buckets = new Map();
  for (const [ts, o, h, l, c, v] of m1) {
    const b = Math.floor(ts / 300000) * 300000;
    if (!buckets.has(b)) buckets.set(b, [o, h, l, c, v]);
    else {
      const a = buckets.get(b);
      a[1] = Math.max(a[1], h);
      a[2] = Math.min(a[2], l);
      a[3] = c;
      a[4] += v;
    }
  }
  return [...buckets.entries()].sort((x, y) => x[0] - y[0]);
}

async function processPair(pair, cfg) {
  const mirrorFile = path.join(SEG_DIR, `${pair}-m5-fsb.csv`);
  if (!fs.existsSync(mirrorFile)) throw new Error(`missing mirror file: ${mirrorFile}`);
  const firstLine = fs.readFileSync(mirrorFile, 'utf8').split('\n')[1];
  if (!firstLine) throw new Error(`mirror file has no candle rows: ${mirrorFile}`);
  const mirrorStart = +firstLine.split(',')[0];

  const endDate = process.env.SMOKE
    ? new Date(FILL_START + 3 * 86400000)
    : new Date(mirrorStart - 1);
  const m1 = [];
  let fetched = 0, skipped404 = 0;

  const cur = new Date(FILL_START);
  while (cur <= endDate) {
    const y = cur.getUTCFullYear();
    const m = cur.getUTCMonth(); // zero-based, matches dukascopy URL scheme
    const d = cur.getUTCDate();
    const url = `${HTTP}/${cfg.code}/${y}/${String(m).padStart(2, '0')}/${String(d).padStart(2, '0')}/BID_candles_min_1.bi5`;
    const cacheFile = path.join(CACHE_DIR, `${pair}-${y}-${m}-${d}.bi5`);

    let gz;
    if (fs.existsSync(cacheFile)) {
      gz = fs.readFileSync(cacheFile);
    } else {
      gz = await fetchUrl(url);
      if (gz) fs.writeFileSync(cacheFile, gz);
    }

    if (gz && gz.length > 0) {
      try {
        m1.push(...decodeDay(gz, Date.UTC(y, m, d), cfg.pip));
        fetched++;
      } catch (e) {
        console.error(`  decode fail ${pair} ${y}-${m + 1}-${d}: ${e.message}`);
      }
    } else {
      skipped404++;
    }

    cur.setUTCDate(cur.getUTCDate() + 1);
  }

  const agg = aggregateM5(m1);
  if (agg.length === 0) throw new Error('no legacy candles downloaded; refusing to write an empty segment');
  const lines = agg.map(
    ([b, o, h, l, c, v]) => `${b},${o.toFixed(cfg.prec)},${h.toFixed(cfg.prec)},${l.toFixed(cfg.prec)},${c.toFixed(cfg.prec)},${Math.round(v)}`
  );
  const outFile = path.join(SEG_DIR, `${pair}-m5-legacy.csv`);
  fs.writeFileSync(outFile, 'timestamp,open,high,low,close,volume\n' + lines.join('\n') + '\n');
  return { bars: agg.length, fetched, skipped404, first: agg[0]?.[0], last: agg[agg.length - 1]?.[0], outFile };
}

(async () => {
  console.log(`[${new Date().toISOString()}] filling legacy gap 2022-09-11 -> mirror start for ${Object.keys(PAIRS).length} pairs`);
  for (const [pair, cfg] of Object.entries(PAIRS)) {
    try {
      const t0 = Date.now();
      const r = await processPair(pair, cfg);
      console.log(
        `[${new Date().toISOString()}] OK ${pair}: ${r.bars} m5 bars (days fetched=${r.fetched}, empty=${r.skipped404}), ${new Date(
          r.first
        ).toISOString()} -> ${new Date(r.last).toISOString()} (${((Date.now() - t0) / 1000).toFixed(0)}s)`
      );
    } catch (e) {
      console.error(`[${new Date().toISOString()}] FAIL ${pair}: ${e.message}`);
    }
  }
  console.log(`[${new Date().toISOString()}] ALL_DONE`);
})();
