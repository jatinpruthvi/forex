/* Resumable two-year M5 CSV download for 11 FX pairs.
   - Fetches four six-month chunks per pair with dukascopy-node.
   - Reuses only complete CSV chunks; writes successful downloads atomically.
   - Retries a 429 only after a seven-minute cooldown; ordinary network errors do not trigger it.
   - Bounded passes avoid an infinite loop when the provider is unavailable.
*/
const { getHistoricalRates } = require('dukascopy-node');
const fs = require('fs');
const path = require('path');

const PAIRS = [
  'eurusd', 'usdjpy', 'gbpusd', 'xauusd', 'eurgbp', 'eurjpy',
  'audusd', 'usdcad', 'nzdusd', 'usdchf', 'gbpjpy'
];

// 6-month chunks covering 2024-09-11 .. 2026-09-11 (UTC).
const CHUNKS = [
  ['2024-09-11', '2025-03-11'],
  ['2025-03-11', '2025-09-11'],
  ['2025-09-11', '2026-03-11'],
  ['2026-03-11', '2026-09-11']
];
const WINDOW_LABEL = '2024-09-11_2026-09-11';
const MAX_PASSES = Math.max(1, Number.parseInt(process.env.MAX_PASSES || '3', 10));
const CSV_HEADER = 'timestamp,open,high,low,close,volume';

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

let cooldownUntil = 0;
const COOLDOWN_MS = 7 * 60 * 1000;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const ts = () => new Date().toISOString();

function isValidCsvFile(file) {
  try {
    const text = fs.readFileSync(file, 'utf8').trim();
    const lines = text.split(/\r?\n/);
    return lines.length > 1 && lines[0] === CSV_HEADER && lines[1].length > 0;
  } catch {
    return false;
  }
}

function isRateLimitError(err) {
  const message = [err?.message, err?.cause?.message, err?.status, err?.cause?.status]
    .filter(Boolean).join(' ');
  return /\b429\b|too many requests|rate.?limit/i.test(message);
}

async function waitOutCooldown() {
  const waitMs = cooldownUntil - Date.now();
  if (waitMs > 0) {
    console.log(`[${ts()}] rate-limited -> cooling down ${Math.ceil(waitMs / 1000)}s before next chunk`);
    await sleep(waitMs);
    cooldownUntil = 0;
  }
}

async function fetchChunk(instrument, from, to) {
  const csv = await getHistoricalRates({
    instrument,
    dates: { from, to },
    ...FETCH_OPTS
  });
  if (typeof csv !== 'string') throw new Error('Downloader returned a non-text CSV payload');
  const lines = csv.trim().split(/\r?\n/);
  if (lines.length < 2 || lines[0] !== CSV_HEADER) {
    throw new Error('Downloader returned an empty or unexpected CSV payload');
  }
  return csv;
}

function assemble(instrument) {
  const parts = CHUNKS.map(([from, to], index) => {
    const file = path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`);
    if (!isValidCsvFile(file)) throw new Error(`invalid or missing chunk: ${file}`);
    const lines = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/);
    return index === 0 ? lines.join('\n') : lines.slice(1).join('\n');
  });
  const outFile = path.join(OUT_DIR, `${instrument}-m5-${WINDOW_LABEL}.csv`);
  const tempFile = `${outFile}.part`;
  fs.writeFileSync(tempFile, parts.join('\n') + '\n', 'utf8');
  fs.renameSync(tempFile, outFile);
  const rows = parts.reduce((total, part) => total + part.split('\n').length, 0) - 1;
  return { outFile, rows };
}

(async () => {
  console.log(`[${ts()}] START chunked downloader: ${PAIRS.length} pairs x ${CHUNKS.length} chunks; max passes=${MAX_PASSES}`);
  let completed = false;

  for (let passCount = 1; passCount <= MAX_PASSES; passCount++) {
    let fetched = 0;
    let failed = 0;
    let remaining = 0;

    for (const instrument of PAIRS) {
      const finalFile = path.join(OUT_DIR, `${instrument}-m5-${WINDOW_LABEL}.csv`);
      if (isValidCsvFile(finalFile)) continue;

      for (const [from, to] of CHUNKS) {
        const chunkFile = path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`);
        if (isValidCsvFile(chunkFile)) continue;
        remaining++;

        await waitOutCooldown();
        console.log(`[${ts()}] FETCH ${instrument} ${from}..${to}`);
        try {
          const csv = await fetchChunk(instrument, from, to);
          const tempFile = `${chunkFile}.part`;
          fs.writeFileSync(tempFile, csv, 'utf8');
          fs.renameSync(tempFile, chunkFile);
          const rows = csv.trim().split(/\r?\n/).length - 1;
          console.log(`[${ts()}] OK ${instrument} ${from}..${to}: ${rows} rows`);
          fetched++;
        } catch (err) {
          failed++;
          if (isRateLimitError(err)) cooldownUntil = Math.max(cooldownUntil, Date.now() + COOLDOWN_MS);
          const msg = err?.validationErrors ? JSON.stringify(err.validationErrors) : err?.message || err;
          console.error(`[${ts()}] FAIL ${instrument} ${from}..${to}: ${msg}`);
        }
        await sleep(1500);
      }

      const finalReady = CHUNKS.every(([from, to]) =>
        isValidCsvFile(path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`))
      );
      if (finalReady) {
        const { outFile, rows } = assemble(instrument);
        console.log(`[${ts()}] ASSEMBLED ${instrument}: ${rows} rows -> ${outFile}`);
      }
    }

    console.log(`[${ts()}] PASS ${passCount} summary: fetched=${fetched} failed=${failed} stillRemaining=${remaining - fetched}`);
    if (remaining === 0 || remaining - fetched === 0) {
      completed = true;
      break;
    }
    if (passCount < MAX_PASSES) await sleep(failed > fetched ? 15000 : 5000);
  }

  if (completed) {
    console.log(`[${ts()}] ALL_DONE`);
  } else {
    console.error(`[${ts()}] INCOMPLETE after ${MAX_PASSES} passes; rerun later to resume missing chunks.`);
    process.exitCode = 1;
  }
})();
