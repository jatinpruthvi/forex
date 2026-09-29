/* Decodes ForexSB dukascopy mirror binary files: 28-byte records:
   [timeMinutes(uint32), open, high, low, close, volume, extra] (uint32 LE, prices x1e5)
   Time epoch hypothesis: minutes since 2000-01-01 UTC. */
const fs = require('fs');

const EPOCH_2000_MS = 946684800000;
const SCALE = 1e5;

function decode(buf) {
  const rec = 28;
  if (buf.length % rec !== 0) {
    throw new Error(`size ${buf.length} not divisible by ${rec}`);
  }
  const n = buf.length / rec;
  const rows = [];
  for (let i = 0; i < n; i++) {
    const o = i * rec;
    rows.push([
      buf.readUInt32LE(o), // minutes since 2000-01-01 UTC
      buf.readUInt32LE(o + 4) / SCALE,
      buf.readUInt32LE(o + 8) / SCALE,
      buf.readUInt32LE(o + 12) / SCALE,
      buf.readUInt32LE(o + 16) / SCALE,
      buf.readUInt32LE(o + 20),
      buf.readUInt32LE(o + 24)
    ]);
  }
  return rows;
}

function show(sym, rows) {
  const fmtTs = t => new Date(EPOCH_2000_MS + t * 60000).toISOString();
  console.log(`\n=== ${sym}: ${rows.length} records ===`);
  console.log('first 2:');
  rows.slice(0, 2).forEach(r => console.log(' ', fmtTs(r[0]), 'O', r[1], 'H', r[2], 'L', r[3], 'C', r[4], 'V', r[5], 'X', r[6]));
  console.log('last 2:');
  rows.slice(-2).forEach(r => console.log(' ', fmtTs(r[0]), 'O', r[1], 'H', r[2], 'L', r[3], 'C', r[4], 'V', r[5], 'X', r[6]));

  // monotonic time?
  let nonMono = 0;
  for (let i = 1; i < rows.length; i++) if (rows[i][0] <= rows[i - 1][0]) nonMono++;
  console.log('non-monotonic timestamps:', nonMono);

  // weekend check on 500 sampled bars
  let weekend = 0;
  for (let i = 0; i < rows.length; i += Math.max(1, Math.floor(rows.length / 500))) {
    const dow = new Date(EPOCH_2000_MS + rows[i][0] * 60000).getUTCDay();
    if (dow === 0 || dow === 6) weekend++;
  }
  console.log('weekend bars in sample of ~500:', weekend);

  // price sanity
  const opens = rows.map(r => r[1]);
  console.log('open range:', Math.min(...opens), '-', Math.max(...opens));

  // typical gap between bars (in minutes) sampled
  const gaps = {};
  for (let i = 1; i < rows.length; i++) {
    const g = rows[i][0] - rows[i - 1][0];
    gaps[g] = (gaps[g] || 0) + 1;
  }
  const topGaps = Object.entries(gaps).sort((a, b) => b[1] - a[1]).slice(0, 4);
  console.log('top time gaps (minutes: count):', topGaps.map(([g, c]) => `${g}:${c}`).join(' '));
}

async function fetchAndDecode(sym) {
  const url = `https://data.forexsb.com/datafeed/data/dukascopy/${sym}5.lb.gz`;
  const res = await fetch(url, { headers: { Referer: 'https://data.forexsb.com/data-app' } });
  if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const rows = decode(buf);
  show(sym, rows);
  fs.writeFileSync(`${sym}5.lb.bin`, buf);
  return rows;
}

(async () => {
  try {
    await fetchAndDecode('EURUSD');
    await fetchAndDecode('USDJPY');
    console.log('\nDECODE OK');
  } catch (e) {
    console.error('DECODE FAIL:', e.message);
  }
})();
