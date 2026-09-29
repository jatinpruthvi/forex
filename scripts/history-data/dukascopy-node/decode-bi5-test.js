/* Prototype: decode one Dukascopy legacy bi5 m1-candle day file and validate vs mirror.
   Candle bi5 record (24 bytes): int32 timeDeltaSec, int32 open*pip, int32 close*pip,
   int32 low*pip, int32 high*pip, float32 volume. Month in URL is zero-based. */
const fs = require('fs');
const path = require('path');
const lzma = require(path.join(__dirname, '..', 'legacy-bi5', 'node_modules', 'lzma-purejs'));

const PIP = { eurusd: 1e5, usdjpy: 1e3, xauusd: 1e3 };

(async () => {
  const buf = fs.readFileSync(path.join(__dirname, 'sample-day.bi5'));
  let out;
  try {
    out = Buffer.from(lzma.decompress(buf));
  } catch (e) {
    console.error('decompress fail:', e.message);
    process.exit(1);
  }
  console.log('decompressed bytes:', out.length, '=> records:', out.length / 24);

  const dayStart = Date.UTC(2024, 0, 10); // 2024-01-10 00:00 UTC
  const rows = [];
  for (let o = 0; o + 24 <= out.length; o += 24) {
    const dt = out.readInt32BE(o); // note: Dukascopy uses big-endian ints
    const open = out.readInt32BE(o + 4) / PIP.eurusd;
    const close = out.readInt32BE(o + 8) / PIP.eurusd;
    const low = out.readInt32BE(o + 12) / PIP.eurusd;
    const high = out.readInt32BE(o + 16) / PIP.eurusd;
    const vol = out.readFloatBE(o + 20);
    rows.push([dayStart + dt * 1000, open, high, low, close, vol]);
  }
  console.log('first:', new Date(rows[0][0]).toISOString(), rows[0].slice(1).join(' '));
  console.log('last :', new Date(rows[rows.length - 1][0]).toISOString(), rows[rows.length - 1].slice(1).join(' '));

  // aggregate m1 00:15..00:19 -> m5 and compare with mirror bar
  const from = Date.UTC(2024, 0, 10, 0, 15), to = Date.UTC(2024, 0, 10, 0, 20);
  const win = rows.filter(r => r[0] >= from && r[0] < to);
  const agg = {
    open: win[0][1],
    high: Math.max(...win.map(r => r[2])),
    low: Math.min(...win.map(r => r[3])),
    close: win[win.length - 1][4]
  };
  console.log('bi5 aggregated m5 :', `O ${agg.open} H ${agg.high} L ${agg.low} C ${agg.close}`);
  console.log('mirror m5 bar     : O 1.09353 H 1.09362 L 1.09344 C 1.09353');
})();
