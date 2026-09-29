/* Runs the 5-year m5 CSV download for all pairs sequentially, logging progress.
   Resumable: skips pairs whose output file already exists. */
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

const FROM = '2021-09-11';
const TO = '2026-09-11';

const outDir = path.join(__dirname, '..', 'm5-data');
fs.mkdirSync(outDir, { recursive: true });

function ts() {
  return new Date().toISOString();
}

(async () => {
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

      fs.writeFileSync(outFile, csv, 'utf8');
      const rows = csv.split('\n').length - 1;
      console.log(
        `[${ts()}] DONE ${instrument}: ${rows} rows, ${(
          (Date.now() - started) /
          1000
        ).toFixed(0)}s -> ${outFile}`
      );
    } catch (err) {
      const msg = err && err.validationErrors ? JSON.stringify(err.validationErrors) : err;
      console.error(`[${ts()}] FAILED ${instrument}: ${msg}`);
    }
  }

  console.log(`[${ts()}] ALL_PAIRS_DONE`);
})();
