/* Downloads 5 years of m5 bid candles as CSV for the instrument given via argv[2] */
const { getHistoricalRates } = require('./dist/index.js');
const fs = require('fs');
const path = require('path');

const instrument = process.argv[2];
if (!instrument) {
  console.error('Usage: node download-m5.js <instrument>');
  process.exit(1);
}

const FROM = '2021-09-11';
const TO = '2026-09-11';

(async () => {
  const started = Date.now();
  console.log(`[${new Date().toISOString()}] fetching ${instrument} m5 ${FROM} -> ${TO} ...`);
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

    const outDir = path.join(__dirname, '..', 'm5-data');
    fs.mkdirSync(outDir, { recursive: true });
    const outFile = path.join(outDir, `${instrument}-m5-${FROM}-${TO}.csv`);
    fs.writeFileSync(outFile, csv, 'utf8');

    const rows = csv.split('\n').length - 1;
    console.log(
      `[${new Date().toISOString()}] DONE ${instrument}: ${rows} rows -> ${outFile} (${(
        (Date.now() - started) /
        1000
      ).toFixed(0)}s)`
    );
  } catch (err) {
    console.error(`[${new Date().toISOString()}] FAILED ${instrument}:`, err);
    process.exit(2);
  }
})();
