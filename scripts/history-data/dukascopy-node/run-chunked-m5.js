/* Resumable M5 history download for 11 FX pairs.
   - Splits the requested date range into bounded calendar-quarter chunks.
   - Limits Dukascopy requests to four concurrent daily downloads per batch.
   - Saves each valid chunk atomically and assembles complete per-pair CSVs.
   - On HTTP 429, waits with exponential backoff and retries the same chunk; if
     the provider is still rate-limiting, exits early so a later Actions run can
     resume from the saved cache instead of continuing to hammer the endpoint.
*/
const fs = require('fs');
const path = require('path');

const PAIRS = [
  'eurusd', 'usdjpy', 'gbpusd', 'xauusd', 'eurgbp', 'eurjpy',
  'audusd', 'usdcad', 'nzdusd', 'usdchf', 'gbpjpy'
];
const CSV_HEADER = 'timestamp,open,high,low,close,volume';
const DEFAULT_FROM = '2021-09-11';
const CHUNK_MONTHS = positiveInteger(process.env.CHUNK_MONTHS, 3);
const MAX_PASSES = positiveInteger(process.env.MAX_PASSES, 3);
const MAX_RATE_LIMIT_RETRIES = positiveInteger(process.env.MAX_RATE_LIMIT_RETRIES, 2);
const RATE_LIMIT_COOLDOWN_MS = positiveInteger(process.env.RATE_LIMIT_COOLDOWN_MS, 7 * 60 * 1000);
const FROM = process.env.HISTORY_FROM || DEFAULT_FROM;
const TO = process.env.HISTORY_TO || new Date().toISOString().slice(0, 10);

const BASE = path.join(__dirname, '..');
const CHUNK_DIR = path.join(BASE, 'm5-chunks');
const OUT_DIR = path.join(BASE, 'm5-data');
const WINDOW_LABEL = `${FROM}_${TO}`;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const ts = () => new Date().toISOString();

function positiveInteger(value, fallback) {
  if (value === undefined || value === '') return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`Expected a positive integer, got: ${value}`);
  }
  return parsed;
}

function parseDate(date) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error(`Invalid date "${date}"; expected YYYY-MM-DD`);
  }
  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date) {
    throw new Error(`Invalid calendar date: ${date}`);
  }
  return parsed;
}

function addMonths(date, months) {
  const result = new Date(date.getTime());
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

function buildDateChunks(from, to, months = 3) {
  const start = parseDate(from);
  const end = parseDate(to);
  if (end <= start) throw new Error(`HISTORY_TO (${to}) must be after HISTORY_FROM (${from})`);
  if (!Number.isInteger(months) || months < 1) throw new Error('Chunk size must be a positive number of months');

  const chunks = [];
  let chunkStart = start;
  while (chunkStart < end) {
    const next = addMonths(chunkStart, months);
    const chunkEnd = next < end ? next : end;
    chunks.push([
      chunkStart.toISOString().slice(0, 10),
      chunkEnd.toISOString().slice(0, 10)
    ]);
    chunkStart = chunkEnd;
  }
  return chunks;
}

const CHUNKS = buildDateChunks(FROM, TO, CHUNK_MONTHS);

function isRateLimitError(err) {
  const message = [err?.message, err?.cause?.message, err?.status, err?.cause?.status]
    .filter(Boolean).join(' ');
  return /\b429\b|too many requests|rate.?limit/i.test(message);
}

function isValidCsvText(text) {
  if (typeof text !== 'string') return false;
  const lines = text.trim().split(/\r?\n/);
  if (lines.length < 2 || lines[0] !== CSV_HEADER || !lines[1]) return false;
  return lines[1].split(',').length === 6;
}

function isValidCsvFile(file) {
  try {
    return isValidCsvText(fs.readFileSync(file, 'utf8'));
  } catch {
    return false;
  }
}

function chunkFilePath(instrument, from, to) {
  return path.join(CHUNK_DIR, `${instrument}-m5-${from}_${to}.csv`);
}

function finalFilePath(instrument) {
  return path.join(OUT_DIR, `${instrument}-m5-${WINDOW_LABEL}.csv`);
}

async function fetchChunk(instrument, from, to) {
  const { getHistoricalRates } = require('dukascopy-node');
  const csv = await getHistoricalRates({
    instrument,
    dates: { from, to },
    timeframe: 'm5',
    priceType: 'bid',
    volumes: true,
    format: 'csv',
    // The old setting (25 concurrent downloads and 500 ms between batches)
    // triggered provider-side HTTP 429s. Keep the request rate deliberately low.
    batchSize: 4,
    pauseBetweenBatchesMs: 2000,
    retryCount: 1,
    pauseBetweenRetriesMs: 3000
  });
  if (!isValidCsvText(csv)) {
    throw new Error('Downloader returned an empty or unexpected CSV payload');
  }
  return csv;
}

async function fetchChunkWithRateLimitRetry(instrument, from, to) {
  for (let retry = 0; ; retry++) {
    try {
      return await fetchChunk(instrument, from, to);
    } catch (err) {
      if (!isRateLimitError(err) || retry >= MAX_RATE_LIMIT_RETRIES) throw err;
      const cooldownMs = RATE_LIMIT_COOLDOWN_MS * (retry + 1);
      console.error(
        `[${ts()}] HTTP 429 for ${instrument} ${from}..${to}; ` +
        `waiting ${Math.ceil(cooldownMs / 60000)} minute(s) before retry ${retry + 1}/${MAX_RATE_LIMIT_RETRIES}`
      );
      await sleep(cooldownMs);
    }
  }
}

function assemble(instrument) {
  const parts = CHUNKS.map(([from, to], index) => {
    const file = chunkFilePath(instrument, from, to);
    if (!isValidCsvFile(file)) throw new Error(`invalid or missing chunk: ${file}`);
    const lines = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/);
    return index === 0 ? lines : lines.slice(1);
  });

  const outFile = finalFilePath(instrument);
  const tempFile = `${outFile}.part`;
  const rows = parts.reduce((total, part) => total + part.length - 1, 0);
  fs.writeFileSync(tempFile, parts.map(part => part.join('\n')).join('\n') + '\n', 'utf8');
  fs.renameSync(tempFile, outFile);
  return { outFile, rows };
}

function hasPendingChunks() {
  return PAIRS.some(instrument => {
    if (isValidCsvFile(finalFilePath(instrument))) return false;
    return CHUNKS.some(([from, to]) => !isValidCsvFile(chunkFilePath(instrument, from, to)));
  });
}

async function run() {
  fs.mkdirSync(CHUNK_DIR, { recursive: true });
  fs.mkdirSync(OUT_DIR, { recursive: true });

  console.log(
    `[${ts()}] START chunked downloader: ${PAIRS.length} pairs x ${CHUNKS.length} chunks, ` +
    `${FROM} -> ${TO}; max passes=${MAX_PASSES}; request batch size=4`
  );
  let completed = false;
  let rateLimited = false;

  passLoop: for (let pass = 1; pass <= MAX_PASSES; pass++) {
    let fetched = 0;
    let failed = 0;

    for (const instrument of PAIRS) {
      if (isValidCsvFile(finalFilePath(instrument))) continue;

      for (const [from, to] of CHUNKS) {
        const chunkFile = chunkFilePath(instrument, from, to);
        if (isValidCsvFile(chunkFile)) continue;

        console.log(`[${ts()}] FETCH ${instrument} ${from}..${to}`);
        try {
          const csv = await fetchChunkWithRateLimitRetry(instrument, from, to);
          const tempFile = `${chunkFile}.part`;
          fs.writeFileSync(tempFile, csv, 'utf8');
          fs.renameSync(tempFile, chunkFile);
          const rows = csv.trim().split(/\r?\n/).length - 1;
          console.log(`[${ts()}] OK ${instrument} ${from}..${to}: ${rows} rows`);
          fetched++;
        } catch (err) {
          failed++;
          const message = err?.validationErrors
            ? JSON.stringify(err.validationErrors)
            : err?.message || String(err);
          console.error(`[${ts()}] FAIL ${instrument} ${from}..${to}: ${message}`);
          if (isRateLimitError(err)) {
            rateLimited = true;
            console.error(`[${ts()}] Provider is still rate-limiting; stopping early. Rerun later to resume saved chunks.`);
            break passLoop;
          }
          continue;
        }

        await sleep(1000);
      }

      const finalReady = CHUNKS.every(([from, to]) => isValidCsvFile(chunkFilePath(instrument, from, to)));
      if (finalReady) {
        const { outFile, rows } = assemble(instrument);
        console.log(`[${ts()}] ASSEMBLED ${instrument}: ${rows} rows -> ${outFile}`);
      }
    }

    console.log(`[${ts()}] PASS ${pass}: fetched=${fetched} failed=${failed} pending=${hasPendingChunks()}`);
    if (!hasPendingChunks()) {
      completed = true;
      break;
    }
    if (pass < MAX_PASSES) await sleep(failed > fetched ? 15000 : 5000);
  }

  if (completed) {
    console.log(`[${ts()}] ALL_DONE`);
    return;
  }

  if (!rateLimited) {
    console.error(`[${ts()}] INCOMPLETE after ${MAX_PASSES} passes; rerun later to resume missing chunks.`);
  }
  process.exitCode = 1;
}

if (require.main === module) {
  run().catch(err => {
    console.error(`[${ts()}] FATAL: ${err?.stack || err}`);
    process.exitCode = 1;
  });
}

module.exports = {
  buildDateChunks,
  isRateLimitError,
  isValidCsvText
};
