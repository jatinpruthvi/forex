/* 5-year m5 CSV downloader for 11 FX pairs, rate-limit-aware.
   - Splits each pair into 6-month chunks (fetched with dukascopy-node, retryCount=5)
   - Multiple passes: a pass only fetches chunks that don't exist yet
   - Between pairs: 20s pause; if >50% of a pass's remaining chunks fail -> cool down 10 min
   - When all chunks of a pair exist -> assembles final CSV in m5-data/
   Safe to re-run: existing chunks and final files are skipped. */
const { getHistoricalRates } = require('./dist/index.js');
const fs = require('fs');
const path = require('path');

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

// 6-month chunks covering 2024-09-11 .. 2026-09-11 (UTC) - 2-year window
const CHUNKS = [
  ['2024-09-11', '2025-03-11'],
  ['2025-03-11', '2025-09-11'],
  ['2025-09-11', '2026-03-11'],
  ['2026-03-11', '2026-09-11']
];

const WINDOW_LABEL = '2024-09-11_2026-09-11';

const BASE = path.join(__dirname, '..');
const CHUNK_DIR = path.join(BASE, 'm5-chunks');
const OUT_DIR = path.join(BASE, 'm5-data');
fs.mkdirSync(CHUNK_DIR, { recursive: true });
fs.mkdirSync(OUT_DIR, { recursive: true });

const FETCH_OPTS = {
  timeframe: 'm5',
  priceType: 'bid',
  volumes: true,
  format: 'csv',
  batchSize: 4,
  pauseBetweenBatchesMs: 1000,
  retryCount: 1,
  pauseBetweenRetriesMs: 8000
};

// Rate-limit handling: after a 429, stop hammering and wait out a cooldown window
let cooldownUntil = 0;
const COOLDOWN_MS = 7 * 60 * 1000;

async function waitOutCooldown() {
  const waitMs = cooldownUntil - Date.now();
  if (waitMs > 0) {
    console.log(
      `[${ts()}] rate-limited -> cooling down ${Math.ceil(waitMs / 1000)}s before next chunk`
    );
    await sleep(waitMs);
    cooldownUntil = 0;
  }
}

function ts() {
  return new Date().toISOString();
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function fetchChunk(instrument, from, to) {
  const csv = await getHistoricalRates({
    instrument,
    dates: { from, to },
    ...FETCH_OPTS
  });
  return csv;
}

function assemble(instrument) {
  const parts = [];
  CHUNKS.forEach(([from, to], i) => {
    const f = path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`);
    let text = fs.readFileSync(f, 'utf8').trimEnd();
    if (i > 0 && text.startsWith('timestamp')) {
      text = text.slice(text.indexOf('\n') + 1); // drop duplicate header row
    }
    parts.push(text);
  });
  const outFile = path.join(OUT_DIR, `${instrument}-m5-${WINDOW_LABEL}.csv`);
  fs.writeFileSync(outFile, parts.join('\n') + '\n', 'utf8');
  const rows = parts.reduce((n, p) => n + (p ? p.split('\n').length : 0), 0);
  return { outFile, rows };
}

(async () => {
  console.log(`[${ts()}] START chunked downloader: ${PAIRS.length} pairs x ${CHUNKS.length} chunks`);
  let passCount = 0;

  while (true) {
    passCount++;
    let fetched = 0;
    let failed = 0;
    let remaining = 0;

    for (const instrument of PAIRS) {
      const finalFile = path.join(OUT_DIR, `${instrument}-m5-${WINDOW_LABEL}.csv`);
      if (fs.existsSync(finalFile)) continue;

      for (const [from, to] of CHUNKS) {
        const chunkFile = path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`);
        if (fs.existsSync(chunkFile)) continue;
        remaining++;

        await waitOutCooldown();

        console.log(`[${ts()}] FETCH ${instrument} ${from}..${to}`);
        try {
          const csv = await fetchChunk(instrument, from, to);
          fs.writeFileSync(chunkFile, typeof csv === 'string' ? csv : '', 'utf8');
          const rows = typeof csv === 'string' ? csv.split('\n').length - 1 : 0;
          console.log(`[${ts()}] OK ${instrument} ${from}..${to}: ${rows} rows`);
          fetched++;
        } catch (err) {
          failed++;
          cooldownUntil = Math.max(cooldownUntil, Date.now() + COOLDOWN_MS);
          const msg =
            err && err.validationErrors ? JSON.stringify(err.validationErrors) : err.message || err;
          console.error(`[${ts()}] FAIL ${instrument} ${from}..${to}: ${msg}`);
        }
        await sleep(1500); // breather between chunks
      }

      const finalReady = CHUNKS.every(([from, to]) =>
        fs.existsSync(path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`))
      );
      if (finalReady) {
        const { outFile, rows } = assemble(instrument);
        console.log(`[${ts()}] ASSEMBLED ${instrument}: ${rows} rows -> ${outFile}`);
      } else {
        await sleep(20000); // pause between incomplete pairs
      }
    }

    console.log(`[${ts()}] PASS ${passCount} summary: fetched=${fetched} failed=${failed} stillRemaining=${remaining - fetched}`);
    if (remaining === 0 || (remaining - fetched) === 0) {
      console.log(`[${ts()}] ALL_DONE`);
      break;
    }

    if (failed > fetched) {
      console.log(`[${ts()}] pass ended with more failures than successes; cooldown logic already applied`);
      await sleep(15000);
    } else {
      await sleep(5000);
    }
  }
})();
