/* Runs the 5-year m5 CSV download for all pairs sequentially, logging progress.
   Resumable: skips pairs whose output file already exists. */
const { getHistoricalRates } = require('dukascopy-node');
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

const FROM = process.env.HISTORY_FROM || '2021-09-11';
const TO = process.env.HISTORY_TO || new Date().toISOString().slice(0, 10);

const outDir = path.join(__dirname, '..', 'm5-data');
fs.mkdirSync(outDir, { recursive: true });

function ts() {
  return new Date().toISOString();
}

(async () => {
  const failedPairs = [];
  console.log(`[${ts()}] START batch of ${PAIRS.length} pairs, ${FROM} -> ${TO}`);

  for (const instrument of PAIRS) {
    const outFile = path.join(outDir, `${instrument}-m5-${FROM}-${TO}.csv`);

    if (fs.existsSync(outFile)) {
      console.log(`[${ts()}] SKIP ${instrument} (file already exists)`);
      continue;
    }

    const started = Date.now();
    console.log(`[${ts()}] FETCH ${instrument} ...`);

    try {
      const csv = await getHistoricalRates({
        instrument,
        dates: { from: FROM, to: TO },
        timeframe: 'm5',
        priceType: 'bid',
        volumes: true,
        format: 'csv',
        batchSize: 25,
        pauseBetweenBatchesMs: 500,
        retryCount: 3,
        pauseBetweenRetriesMs: 1000
      });

      if (typeof csv !== 'string' || !csv.startsWith('timestamp,open,high,low,close,volume')) {
        throw new Error('Downloader returned an empty or unexpected CSV payload');
      }
      const rows = csv.trim().split(/\r?\n/).length - 1;
      if (rows < 1) throw new Error('Downloader returned no candle rows');
      const tempFile = `${outFile}.part`;
      fs.writeFileSync(tempFile, csv, 'utf8');
      fs.renameSync(tempFile, outFile);
      console.log(
        `[${ts()}] DONE ${instrument}: ${rows} rows, ${(
          (Date.now() - started) /
          1000
        ).toFixed(0)}s -> ${outFile}`
      );
    } catch (err) {
      const msg = err && err.validationErrors ? JSON.stringify(err.validationErrors) : err;
      failedPairs.push(instrument);
      console.error(`[${ts()}] FAILED ${instrument}: ${msg}`);
    }
  }

  if (failedPairs.length > 0) {
    console.error(`[${ts()}] FAILED_PAIRS: ${failedPairs.join(', ')}`);
    process.exitCode = 1;
  } else {
    console.log(`[${ts()}] ALL_PAIRS_DONE`);
  }
})();
