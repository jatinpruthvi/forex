/* Downloads all 11 pairs from the ForexSB dukascopy mirror (200k latest m5 bars each),
   decodes the 28-byte binary records, and writes dukascopy-node-style CSVs.
   Record: [minutesSince2000(uint32), open, high, low, close, volume, extra] as uint32 LE, prices x1e5 */
const fs = require('fs');
const path = require('path');

const EPOCH_2000_MS = 946684800000;
const SCALE = 1e5;
const REC = 28;

const PAIRS = [
  'eurusd',
  'usdjpy',
  'gbpusd',
  'xauusd',
  'eurgbp',
  'eurjpy',
  'audusd',
  'usdcad',
  'nzdusd',
  'usdchf',
  'gbpjpy'
];

// Price decimal precision per pair (Dukascopy/FX convention: 3 for JPY quotes & gold, 5 otherwise)
const PRECISION = {
  eurusd: 5,
  usdjpy: 3,
  gbpusd: 5,
  xauusd: 3,
  eurgbp: 5,
  eurjpy: 3,
  audusd: 5,
  usdcad: 5,
  nzdusd: 5,
  usdchf: 5,
  gbpjpy: 3
};

// FSB symbol codes differ only in casing; mirror uses uppercase, e.g. EURUSD5
const HEADERS = 'timestamp,open,high,low,close,volume';

const OUT_DIR = path.join(__dirname, '..', 'm5-data');
const SEG_DIR = path.join(OUT_DIR, 'intermediates'); // per-segment files (mirror segment only)
const RAW_DIR = path.join(__dirname, 'fsb-raw');
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.mkdirSync(SEG_DIR, { recursive: true });
fs.mkdirSync(RAW_DIR, { recursive: true });

function decode(buf, precision) {
  if (buf.length % REC !== 0) throw new Error(`size ${buf.length} not divisible by ${REC}`);
  const n = buf.length / REC;
  const scale = Math.pow(10, precision);
  const lines = new Array(n);
  for (let i = 0; i < n; i++) {
    const o = i * REC;
    const ts = EPOCH_2000_MS + buf.readUInt32LE(o) * 60000;
    const open = (buf.readUInt32LE(o + 4) / scale).toFixed(precision);
    const high = (buf.readUInt32LE(o + 8) / scale).toFixed(precision);
    const low = (buf.readUInt32LE(o + 12) / scale).toFixed(precision);
    const close = (buf.readUInt32LE(o + 16) / scale).toFixed(precision);
    const vol = buf.readUInt32LE(o + 20);
    lines[i] = `${ts},${open},${high},${low},${close},${vol}`;
  }
  return lines;
}

async function fetchPair(sym) {
  const url = `https://data.forexsb.com/datafeed/data/dukascopy/${sym.toUpperCase()}5.lb.gz`;
  const headers = {
    Referer: 'https://data.forexsb.com/data-app',
    'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36'
  };

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, { headers });
      if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
      const data = Buffer.from(await res.arrayBuffer());
      if (data.length === 0) throw new Error('empty response body');
      return data;
    } catch (err) {
      if (attempt === 3) throw err;
      const pauseMs = 1000 * 2 ** (attempt - 1);
      console.warn(`[${new Date().toISOString()}] retry ${sym} ${attempt}/3 after ${pauseMs}ms: ${err.message}`);
      await new Promise(resolve => setTimeout(resolve, pauseMs));
    }
  }
}

/* Node fetch auto-decompresses gzip; decompress only if body is still raw gzip (magic 1f 8b) */
function maybeGunzip(buf) {
  if (buf.length > 2 && buf[0] === 0x1f && buf[1] === 0x8b) {
    return require('zlib').gunzipSync(buf);
  }
  return buf;
}

(async () => {
  const failures = [];
  console.log(`[${new Date().toISOString()}] fetching ${PAIRS.length} pairs from ForexSB mirror`);
  for (const pair of PAIRS) {
    const outFile = path.join(SEG_DIR, `${pair}-m5-fsb.csv`);
    try {
      const gz = await fetchPair(pair);
      const buf = maybeGunzip(gz);
      const lines = decode(buf, PRECISION[pair]);
      if (lines.length === 0) throw new Error('response decoded to zero candles');

      const firstTs = +lines[0].split(',')[0];
      const lastTs = +lines[lines.length - 1].split(',')[0];
      fs.writeFileSync(path.join(RAW_DIR, `${pair}5.lb.gz`), gz);
      const tempFile = `${outFile}.part`;
      fs.writeFileSync(tempFile, HEADERS + '\n' + lines.join('\n') + '\n', 'utf8');
      fs.renameSync(tempFile, outFile);

      console.log(
        `[${new Date().toISOString()}] OK ${pair}: ${lines.length} bars, ${new Date(
          firstTs
        ).toISOString()} -> ${new Date(lastTs).toISOString()} -> ${outFile}`
      );
    } catch (e) {
      failures.push(pair);
      console.error(`[${new Date().toISOString()}] FAIL ${pair}: ${e.message}`);
    }
  }
  if (failures.length > 0) {
    console.error(`[${new Date().toISOString()}] FAILED_PAIRS: ${failures.join(', ')}`);
    process.exitCode = 1;
  } else {
    console.log(`[${new Date().toISOString()}] ALL_DONE`);
  }
})();
