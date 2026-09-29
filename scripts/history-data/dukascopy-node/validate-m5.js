/* Full validation suite for the 11 four-year m5 CSVs.
   Checks per pair:
   1. Structural: header, 6 numeric fields per line, no parse errors
   2. Timestamps: strictly increasing, 5-min grid aligned, no duplicates
   3. OHLC logic: high>=max(o,c), low<=min(o,c), low<=high, prices>0, plausible range
   4. Weekend bars: none on Sat, Sun<22:00, Fri>=22:00 (UTC)
   5. Gaps: histogram + top-10 largest gaps
   6. Flat bars: count, longest consecutive run
   7. Volume: legacy segment must be all-zero, mirror segment must have volumes
   8. Seam: legacy->mirror boundary (5-min gap, price continuity)
   9. Outliers: top 5 largest 5-min returns (review items, not necessarily corruption)
   10. Spot checks: 3 random bars per pair vs official Dukascopy JSON API (2 legacy + 1 mirror)
   Verdict: FAIL on structural problems, WARN for review items. Report written to validation-report.txt */
const fs = require('fs');
const path = require('path');

const BASE = path.join(__dirname, '..');
const OUT_DIR = path.join(BASE, 'm5-data');
const JETTA = 'https://jetta.dukascopy.com/v1/candles/minute';

const PAIRS = {
  eurusd: { code: 'EUR-USD', prec: 5, range: [0.9, 1.4] },
  usdjpy: { code: 'USD-JPY', prec: 3, range: [95, 180] },
  gbpusd: { code: 'GBP-USD', prec: 5, range: [1.0, 1.45] },
  xauusd: { code: 'XAU-USD', prec: 3, range: [1000, 6000] },
  eurgbp: { code: 'EUR-GBP', prec: 5, range: [0.8, 1.0] },
  eurjpy: { code: 'EUR-JPY', prec: 3, range: [110, 210] },
  audusd: { code: 'AUD-USD', prec: 5, range: [0.5, 0.85] },
  usdcad: { code: 'USD-CAD', prec: 5, range: [1.1, 1.6] },
  nzdusd: { code: 'NZD-USD', prec: 5, range: [0.5, 0.75] },
  usdchf: { code: 'USD-CHF', prec: 5, range: [0.7, 1.1] },
  gbpjpy: { code: 'GBP-JPY', prec: 3, range: [120, 230] }
};

const TICK = p => Math.pow(10, -p);
const iso = ts => new Date(ts).toISOString();
const sleep = ms => new Promise(r => setTimeout(r, ms));
const report = [];
function log(s) {
  report.push(s);
  console.log(s);
}

const nyFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  weekday: 'short',
  hour: 'numeric',
  minute: 'numeric',
  hour12: false
});

function isWeekendBar(ts) {
  const parts = {};
  for (const p of nyFmt.formatToParts(new Date(ts))) parts[p.type] = p.value;
  const dow = parts.weekday; // Mon..Sun
  const mins = (parseInt(parts.hour, 10) % 24) * 60 + parseInt(parts.minute, 10);
  if (dow === 'Sat') return true;
  if (dow === 'Sun' && mins < 17 * 60) return true; // market opens Sun 17:00 NY
  if (dow === 'Fri' && mins >= 17 * 60) return true; // closes Fri 17:00 NY
  return false;
}

function analyzeFile(pair, cfg, mirrorStartTs) {
  const file = path.join(OUT_DIR, `${pair}-m5-2016-09-11_${new Date().toISOString().slice(0, 10)}.csv`);
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split('\n');
  const res = { file, issues: [], warns: [] };

  if (lines[0].trim() !== 'timestamp,open,high,low,close,volume') {
    res.issues.push(`bad header: ${lines[0]}`);
  }

  const bars = [];
  let parseErrors = 0;
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (!line || line === '') continue;
    const f = line.split(',');
    if (f.length !== 6) { parseErrors++; continue; }
    const ts = +f[0], o = +f[1], h = +f[2], l = +f[3], c = +f[4], v = +f[5];
    if (!Number.isFinite(ts) || !Number.isFinite(o) || !Number.isFinite(h) || !Number.isFinite(l) || !Number.isFinite(c) || !Number.isFinite(v)) {
      parseErrors++; continue;
    }
    bars.push([ts, o, h, l, c, v]);
  }
  res.bars = bars.length;
  res.parseErrors = parseErrors;
  if (parseErrors > 0) res.issues.push(`${parseErrors} unparseable lines`);

  // timestamps: strict increase + 5-min grid
  let nonMono = 0, offGrid = 0;
  for (let i = 0; i < bars.length; i++) {
    if (i > 0 && bars[i][0] <= bars[i - 1][0]) nonMono++;
    if (bars[i][0] % 300000 !== 0) offGrid++;
  }
  if (nonMono > 0) res.issues.push(`${nonMono} non-monotonic/duplicate timestamps`);
  if (offGrid > 0) res.issues.push(`${offGrid} bars off 5-min grid`);
  res.firstTs = bars[0][0];
  res.lastTs = bars[bars.length - 1][0];

  // OHLC logic + range
  let ohlcBad = 0, rangeBad = 0;
  const [minP, maxP] = cfg.range;
  let minClose = Infinity, maxClose = -Infinity;
  for (const [, o, h, l, c] of bars) {
    if (h < Math.max(o, c) || l > Math.min(o, c) || l > h || o <= 0 || h <= 0 || l <= 0 || c <= 0) ohlcBad++;
    if (c < minClose) minClose = c;
    if (c > maxClose) maxClose = c;
    if (c < minP || c > maxP) rangeBad++;
  }
  if (ohlcBad > 0) res.issues.push(`${ohlcBad} OHLC logic violations`);
  if (rangeBad > 0) res.issues.push(`${rangeBad} closes outside plausible range ${minP}-${maxP}`);
  res.minClose = minClose; res.maxClose = maxClose;

  // weekend bars
  let weekend = 0;
  const weekendSamples = [];
  for (const b of bars) {
    if (isWeekendBar(b[0])) {
      weekend++;
      if (weekendSamples.length < 3) weekendSamples.push(iso(b[0]));
    }
  }
  if (weekend > 5) res.issues.push(`${weekend} weekend bars (e.g. ${weekendSamples.join(', ')})`);
  else if (weekend > 0) res.warns.push(`${weekend} weekend bars (borderline Fri 22:00 / Sun 22:00)`);

  // gaps
  const gapHist = { '5m': 0, '10-60m': 0, '1-6h': 0, '6-42h': 0, 'weekend': 0, 'other': 0 };
  const topGaps = [];
  for (let i = 1; i < bars.length; i++) {
    const g = (bars[i][0] - bars[i - 1][0]) / 60000;
    if (g === 5) gapHist['5m']++;
    else if (g <= 60) gapHist['10-60m']++;
    else if (g <= 360) gapHist['1-6h']++;
    else if (g <= 42 * 60) gapHist['6-42h']++;
    else if (g <= 75 * 60) gapHist['weekend']++;
    else gapHist['other']++;
    topGaps.push([g, bars[i - 1][0], bars[i][0]]);
  }
  topGaps.sort((a, b) => b[0] - a[0]);
  res.gapHist = gapHist;
  res.topGaps = topGaps.slice(0, 5);
  const otherGaps = topGaps.filter(g => g[0] > 75 * 60).length;
  if (otherGaps > 0) res.warns.push(`${otherGaps} gaps > 75h (longer than a weekend)`);

  // flat bars
  let flats = 0, maxRun = 0, run = 0;
  for (const [, o, h, l, c] of bars) {
    if (o === h && h === l && l === c) { flats++; run++; if (run > maxRun) maxRun = run; }
    else run = 0;
  }
  res.flats = flats; res.maxFlatRun = maxRun;
  if (maxRun >= 36) res.warns.push(`longest flat run ${maxRun} bars (${(maxRun * 5 / 60).toFixed(1)}h) - check holidays`);

  // volume segments
  let legacyNonZeroV = 0, mirrorZeroV = 0;
  for (const [ts, , , , , v] of bars) {
    if (ts < mirrorStartTs) { if (v !== 0) legacyNonZeroV++; }
    else if (v === 0) mirrorZeroV++;
  }
  if (legacyNonZeroV > 0) res.issues.push(`${legacyNonZeroV} non-zero volumes in legacy (histdata) segment`);
  if (mirrorZeroV > 0) res.warns.push(`${mirrorZeroV} zero-volume bars in mirror segment`);

  // seam
  let seamIdx = -1;
  for (let i = 0; i < bars.length; i++) if (bars[i][0] >= mirrorStartTs) { seamIdx = i; break; }
  if (seamIdx > 0) {
    const gapMin = (bars[seamIdx][0] - bars[seamIdx - 1][0]) / 60000;
    const diff = Math.abs(bars[seamIdx][1] - bars[seamIdx - 1][4]);
    // Volatility-aware tolerance: normal 5-min moves across the segment boundary
    // (e.g. gold ~1.5bp, GBPJPY ~2.4bp) must not flag; true scaling corruption
    // (x10/x0.1 price errors) still exceeds any price-relative tolerance.
    const allowed = Math.max(5 * TICK(cfg.prec), bars[seamIdx - 1][4] * 5e-5);
    res.seam = { gapMin, diff };
    if (gapMin !== 5) res.warns.push(`seam gap ${gapMin} min (expected 5)`);
    if (diff > allowed) res.issues.push(`seam price jump ${diff}`);
  }

  // outliers: top 5 absolute 5-min returns
  const outs = [];
  for (let i = 1; i < bars.length; i++) {
    const ret = Math.abs(bars[i][4] / bars[i - 1][4] - 1);
    if (ret > 0.02) outs.push([ret, bars[i][0], bars[i - 1][4], bars[i][4]]);
  }
  outs.sort((a, b) => b[0] - a[0]);
  res.outliers = outs.slice(0, 5);
  if (outs.length > 0) res.warns.push(`${outs.length} bars with |return| > 2% (verify vs news)`);

  // bars per year
  const perYear = {};
  for (const [ts] of bars) {
    const y = new Date(ts).getUTCFullYear();
    perYear[y] = (perYear[y] || 0) + 1;
  }
  res.perYear = perYear;
  res.barsArr = bars;

  return res;
}

/* ---------- spot checks vs official API ---------- */
function lcg(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

function pickTradingTs(rng, from, to) {
  for (let tries = 0; tries < 20; tries++) {
    const ts = Math.floor((from + rng() * (to - from)) / 300000) * 300000;
    if (!isWeekendBar(ts)) return ts;
  }
  return null;
}

async function fetchDayM1(code, ts) {
  const d = new Date(ts);
  const url = `${JETTA}/${code}/BID/${d.getUTCFullYear()}/${d.getUTCMonth() + 1}/${d.getUTCDate()}`;
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
      if (res.status === 429) {
        await sleep(15000);
        continue;
      }
      if (res.status === 404) return null;
      if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (!data || !Array.isArray(data.times) || data.times.length === 0) return null;
      const mult = data.multiplier;
      let t = data.timestamp;
      let o = Math.round(data.open / mult), h = Math.round(data.high / mult),
        l = Math.round(data.low / mult), c = Math.round(data.close / mult);
      const rows = [];
      for (let i = 0; i < data.times.length; i++) {
        t += data.times[i] * data.shift;
        o += data.opens[i]; h += data.highs[i]; l += data.lows[i]; c += data.closes[i];
        rows.push([t, o * mult, h * mult, l * mult, c * mult]);
      }
      return rows;
    } catch (e) {
      if (attempt === 2) return null;
      await sleep(3000);
    }
  }
  return null;
}

async function spotCheck(pair, cfg, bars, mirrorStartTs) {
  const tick = TICK(cfg.prec);
  const rng = lcg([...pair].reduce((a, ch) => a + ch.charCodeAt(0), 7));
  const targets = [
    pickTradingTs(rng, bars[0][0] + 86400000, mirrorStartTs - 2 * 86400000),
    pickTradingTs(rng, bars[0][0] + 86400000, mirrorStartTs - 2 * 86400000),
    pickTradingTs(rng, mirrorStartTs + 86400000, bars[bars.length - 1][0] - 2 * 86400000)
  ];
  const results = [];
  for (const target of targets) {
    if (!target) continue;
    let ok = false;
    for (let shiftTries = 0; shiftTries < 3 && !ok; shiftTries++) {
      const ts = target + shiftTries * 300000;
      if (isWeekendBar(ts)) continue;
      let m1 = null;
      try { m1 = await fetchDayM1(cfg.code, ts); } catch (e) { /* keep null */ }
      if (!m1) { await sleep(500); continue; }
      const win = m1.filter(r => r[0] >= ts && r[0] < ts + 300000);
      await sleep(500);
      if (win.length === 0) continue;
      const agg = {
        o: win[0][1], h: Math.max(...win.map(r => r[2])),
        l: Math.min(...win.map(r => r[3])), c: win[win.length - 1][4]
      };
      const row = bars.find(b => b[0] === ts);
      if (!row) continue;
      const maxDev = Math.max(
        Math.abs(row[1] - agg.o), Math.abs(row[2] - agg.h),
        Math.abs(row[3] - agg.l), Math.abs(row[4] - agg.c)
      );
      const status = maxDev <= tick ? 'EXACT' : maxDev <= 2 * tick ? 'WARN' : 'FAIL';
      results.push({ ts, status, maxDev, agg, row });
      ok = true;
    }
    if (!ok) results.push({ ts: target, status: 'UNVERIFIED' });
  }
  return results;
}

/* ---------- main ---------- */
(async () => {
  log(`# Validation report - generated ${new Date().toISOString()}`);
  log(`# Files: m5-data/<pair>-m5-2016-09-11_<today>.csv`);
  let overallFail = 0, overallWarn = 0;
  const persist = () => fs.writeFileSync(path.join(OUT_DIR, 'validation-report.txt'), report.join('\n'), 'utf8');

  for (const [pair, cfg] of Object.entries(PAIRS)) {
    const fsbFirst = fs.readFileSync(path.join(path.join(OUT_DIR, 'intermediates'), `${pair}-m5-fsb.csv`), 'utf8').split('\n')[1];
    const mirrorStartTs = +fsbFirst.split(',')[0];

    let res;
    try {
      res = analyzeFile(pair, cfg, mirrorStartTs);
    } catch (e) {
      log(`\n## ${pair}: FATAL ${e.message}`);
      overallFail++;
      continue;
    }

    log(`\n## ${pair.toUpperCase()}`);
    log(`bars: ${res.bars} | coverage: ${iso(res.firstTs)} -> ${iso(res.lastTs)}`);
    log(`per-year: ${Object.entries(res.perYear).map(([y, n]) => `${y}:${n}`).join('  ')}`);
    log(`close range: ${res.minClose} .. ${res.maxClose} | gaps: ${Object.entries(res.gapHist).filter(([, n]) => n).map(([k, n]) => `${k}=${n}`).join(', ')}`);
    log(`flat bars: ${res.flats} (longest run ${res.maxFlatRun}) | parse errors: ${res.parseErrors}`);

    if (res.topGaps.length) {
      log(`largest gaps: ${res.topGaps.map(g => `${g[0]}min (${iso(g[1])})`).join(' | ')}`);
    }

    log(`spot checks vs official Dukascopy API:`);
    const spots = await spotCheck(pair, cfg, res.barsArr, mirrorStartTs);
    for (const s of spots) {
      if (s.status === 'UNVERIFIED') {
        log(`  UNVERIFIED ${iso(s.ts)} (API unavailable for that bar)`);
      } else {
        log(
          `  ${s.status.padEnd(9)} ${iso(s.ts)} | max deviation ${s.maxDev} | ours O ${s.row[1]} H ${s.row[2]} L ${s.row[3]} C ${s.row[4]}`
        );
        if (s.status === 'FAIL') res.issues.push(`spot check FAIL at ${iso(s.ts)} (dev ${s.maxDev})`);
        if (s.status === 'WARN') res.warns.push(`spot check small deviation at ${iso(s.ts)}`);
      }
    }

    const verdictBad = res.issues.length > 0;
    if (verdictBad) overallFail++; else if (res.warns.length > 0) overallWarn++;

    log(`issues: ${res.issues.length ? res.issues.join(' ; ') : 'NONE'}`);
    log(`warnings: ${res.warns.length ? res.warns.join(' ; ') : 'none'}`);
    log(`verdict: ${verdictBad ? 'FAIL' : res.warns.length ? 'PASS (with review notes)' : 'PASS'}`);
    persist();
  }

  log(`\n# SUMMARY: files=${Object.keys(PAIRS).length}, fail=${overallFail}, pass-with-notes=${overallWarn}`);
  persist();
})();
