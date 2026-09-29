/* Remove bars in the 4 anomalous Sunday 20:00-20:59 UTC hour-buckets (DST-transition
   artifacts in the legacy segment) from the final 4-year CSVs, in place. */
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, '..', 'm5-data');
const PAIRS = [
  'eurusd', 'usdjpy', 'gbpusd', 'xauusd', 'eurgbp', 'eurjpy',
  'audusd', 'usdcad', 'nzdusd', 'usdchf', 'gbpjpy'
];

const TRIM_HOURS = new Set([
  '2022-10-30T20', '2023-03-12T20', '2023-03-19T20', '2023-10-29T20'
]);

for (const pair of PAIRS) {
  const file = path.join(OUT_DIR, `${pair}-m5-2022-09-11_2026-09-11.csv`);
  const lines = fs.readFileSync(file, 'utf8').trim().split('\n');
  const header = lines[0];
  const kept = [];
  let removed = 0;
  for (let i = 1; i < lines.length; i++) {
    const ts = +lines[i].split(',')[0];
    const key = new Date(ts).toISOString().slice(0, 13);
    if (TRIM_HOURS.has(key)) { removed++; continue; }
    kept.push(lines[i]);
  }
  fs.writeFileSync(file, header + '\n' + kept.join('\n') + '\n');
  console.log(`${pair}: removed ${removed} bars, ${kept.length} kept`);
}
console.log('TRIM_DONE');
