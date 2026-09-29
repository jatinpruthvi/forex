/* Remove bars in the Sunday 20:00-20:59 UTC hour-buckets of DST-transition days
   (artifacts of the legacy segment's clock around EU/US DST changes) from the
   final m5 CSVs, in place. Transition dates are generated for the full data
   coverage (2016 -> present) instead of a hardcoded list: both EU and US
   calendars, since the mirror+histdata seam sits inside both windows. */
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, '..', 'm5-data');
const PAIRS = [
  'eurusd', 'usdjpy', 'gbpusd', 'xauusd', 'eurgbp', 'eurjpy',
  'audusd', 'usdcad', 'nzdusd', 'usdchf', 'gbpjpy'
];

const START_YEAR = 2016;
const END_YEAR = new Date().getUTCFullYear();

function lastSundayUtcMonthDay(year, month /* 0-based */) {
  const last = new Date(Date.UTC(year, month + 1, 0));
  return String(last.getUTCDate() - last.getUTCDay()).padStart(2, '0');
}
function nthSundayUtcMonthDay(year, month /* 0-based */, n) {
  const first = new Date(Date.UTC(year, month, 1));
  return String(1 + ((7 - first.getUTCDay()) % 7) + 7 * (n - 1)).padStart(2, '0');
}

const keys = new Set();
for (let y = START_YEAR; y <= END_YEAR; y++) {
  // EU calendar: last Sunday of March / last Sunday of October
  keys.add(`${y}-03-${lastSundayUtcMonthDay(y, 2)}T20`);
  keys.add(`${y}-10-${lastSundayUtcMonthDay(y, 9)}T20`);
  // US calendar: 2nd Sunday of March / 1st Sunday of November
  keys.add(`${y}-03-${nthSundayUtcMonthDay(y, 2, 2)}T20`);
  keys.add(`${y}-11-${nthSundayUtcMonthDay(y, 10, 1)}T20`);
}

for (const pair of PAIRS) {
  const file = path.join(OUT_DIR, `${pair}-m5-2016-09-11_${new Date().toISOString().slice(0, 10)}.csv`);
  if (!fs.existsSync(file)) {
    console.log(`SKIP ${pair} (${file} not found)`);
    continue;
  }
  const lines = fs.readFileSync(file, 'utf8').trim().split('\n');
  const header = lines[0];
  const kept = [];
  let removed = 0;
  for (let i = 1; i < lines.length; i++) {
    const ts = +lines[i].split(',')[0];
    const key = new Date(ts).toISOString().slice(0, 13);
    if (keys.has(key)) { removed++; continue; }
    kept.push(lines[i]);
  }
  fs.writeFileSync(file, header + '\n' + kept.join('\n') + '\n');
  console.log(`${pair}: removed ${removed} bars, ${kept.length} kept`);
}
console.log('TRIM_DONE');
