/* Full validation suite for the 11 two-year M1 CSVs (m1-data/<pair>-m1-2024-09-11_2026-09-11.csv).
   Checks per pair:
   1. Structural: header, 6 numeric fields per line, no parse errors
   2. Timestamps: strictly increasing, 1-min grid aligned, no duplicates
   3. OHLC logic: high>=max(o,c), low<=min(o,c), prices>0, plausible range
   4. Weekend bars: none on Sat, Sun<17:00, Fri>=17:00 (New York time)
   5. Gaps: histogram + top-10 largest gaps
   6. Flat bars: count, longest consecutive run
   7. Volume: legacy segment all-zero, mirror segment has volumes
   8. Seam: legacy->mirror boundary (1-min gap, price continuity)
   9. Outliers: top 5 largest 1-min returns (review items)
   10. Spot checks: 3 random bars per pair vs official Dukascopy JSON API (exact single-minute bars)
   Verdict: FAIL on structural problems, PASS (with review notes) for warnings. */
const fs = require('fs');
const path = require('path');

const BASE = path.join(__dirname, '..');
const OUT_DIR = path.join(BASE, 'm1-data');
const SEG_DIR = path.join(OUT_DIR, 'intermediates');
const JETTA = 'https://jetta.dukascopy.com/v1/candles/minute';
const STEP = 60000; // 1 minute

const PAIRS = {
  eurusd: { code: 'EUR-USD', prec: 5, range: [0.9, 1.4] },
  usdjpy: { code: 'USD-JPY', prec: 3, range: [120, 180] },
  gbpusd: { code: 'GBP-USD', prec: 5, range: [1.0, 1.45] },
  xauusd: { code: 'XAU-USD', prec: 3, range: [1500, 6000] },
  eurgbp: { code: 'EUR-GBP', prec: 5, range: [0.8, 1.0] },
  eurjpy: { code: 'EUR-JPY', prec: 3, range: [130, 210] },
  audusd: { code: 'AUD-USD', prec: 5, range: [0.5, 0.85] },
  usdcad: { code: 'USD-CAD', prec: 5, range: [1.1, 1.6] },
  nzdusd: { code: 'NZD-USD', prec: 5, range: [0.5, 0.75] },
  usdchf: { code: 'USD-CHF', prec: 5, range: [0.7, 1.1] },
  gbpjpy: { code: 'GBP-JPY', prec: 3, range: [140, 230] }
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
  const dow = parts.weekday;
  const mins = (parseInt(parts.hour, 10) % 24) * 60 + parseInt(parts.minute, 10);
  if (dow === 'Sat') return true;
  if (dow === 'Sun' && mins < 17 * 60) return true;
  if (dow === 'Fri' && mins >= 17 * 60) return true;
  return false;
}

function analyzeFile(pair, cfg) {
  const file = path.join(OUT_DIR, `${pair}-m1-2024-09-11_2026-09-11.csv`);
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
    if (![ts, o, h, l, c, v].every(Number.isFinite)) { parseErrors++; continue; }
    bars.push([ts, o, h, l, c, v]);
  }
  res.bars = bars.length;
  res.parseErrors = parseErrors;
  if (parseErrors > 0) res.issues.push(`${parseErrors} unparseable lines`);

  // timestamps: strict increase + 1-min grid
  let nonMono = 0, offGrid = 0;
  for (let i = 0; i < bars.length; i++) {
    if (i > 0 && bars[i][0] <= bars[i - 1][0]) nonMono++;
    if (bars[i][0] % STEP !== 0) offGrid++;
  }
  if (nonMono > 0) res.issues.push(`${nonMono} non-monotonic/duplicate timestamps`);
  if (offGrid > 0) res.issues.push(`${offGrid} bars off 1-min grid`);
  res.firstTs = bars[0][0];
  res.lastTs = bars[bars.length - 1][0];

  // OHLC logic + price plausibility
  let ohlc = 0, outOfRange = 0;
  for (const [ts, o, h, l, c] of bars) {
    if (h < Math.max(o, c) - 1e-9 || l > Math.min(o, c) + 1e-9 || l > h + 1e-9 || o <= 0 || l <= 0) ohlc++;
    if (c < cfg.range[0] || c > cfg.range[1]) outOfRange++;
  }
  if (ohlc > 0) res.issues.push(`${ohlc} OHLC logic violations`);
  if (outOfRange > 0) res.issues.push(`${outOfRange} bars outside plausible band ${cfg.range}`);

  // weekend bars
  let weekend = 0;
  for (const b of bars) if (isWeekendBar(b[0])) weekend++;
  if (weekend > 0) res.issues.push(`${weekend} weekend bars (outside NY-time FX week)`);

  // gaps
  const gapHist = { '1min': 0, '2-5min': 0, '6-15min': 0, '16-60min': 0, '1-3h': 0, '3-24h': 0, 'weekend~48h': 0, '>48h': 0 };
  const topGaps = [];
  for (let i = 1; i < bars.length; i++) {
    const dmin = (bars[i][0] - bars[i - 1][0]) / 60000;
    if (dmin <= 1) gapHist['1min']++;
    else if (dmin <= 5) gapHist['2-5min']++;
    else if (dmin <= 15) gapHist['6-15min']++;
    else if (dmin <= 60) gapHist['16-60min']++;
    else if (dmin <= 180) gapHist['1-3h']++;
    else if (dmin <= 1440) gapHist['3-24h']++;
    else if (dmin <= 2900) gapHist['weekend~48h']++;
    else gapHist['>48h']++;
    if (dmin > 60) topGaps.push([dmin, bars[i][0] - dmin * 60000]);
  }
  res.gapHist = gapHist;
  topGaps.sort((a, b) => b[0] - a[0]);
  res.topGaps = topGaps.slice(0, 10);

  // flat bars & runs
  let flats = 0, maxRun = 0, run = 0;
  for (let i = 0; i < bars.length; i++) {
    if (bars[i][1] === bars[i][2] && bars[i][2] === bars[i][3] && bars[i][3] === bars[i][4]) {
      flats++; run++; if (run > maxRun) maxRun = run;
    } else run = 0;
  }
  res.flats = flats;
  res.maxFlatRun = maxRun;

  // volume segments
  const fsbStart = res.fsbStart = +fs.readFileSync(path.join(SEG_DIR, `${pair}-m1-fsb.csv`), 'utf8').split('\n')[1].split(',')[0];
  let legacyVolNonZero = 0, mirrorVolZero = 0;
  for (const b of bars) {
    if (b[0] < fsbStart) { if (b[5] !== 0) legacyVolNonZero++; }
    else if (b[5] === 0) mirrorVolZero++;
  }
  if (legacyVolNonZero > 0) res.issues.push(`${legacyVolNonZero} legacy bars with nonzero volume (expected 0)`);
  if (mirrorVolZero > 0) res.warns.push(`${mirrorVolZero} mirror bars with zero volume`);

  // seam: last legacy bar vs first mirror bar
  const legacyLast = bars.filter(b => b[0] < fsbStart).pop();
  const mirrorFirst = bars.find(b => b[0] >= fsbStart);
  if (legacyLast && mirrorFirst) {
    const seamMin = (mirrorFirst[0] - legacyLast[0]) / 60000;
    const tick = TICK(cfg.prec);
    const seamDev = Math.abs(mirrorFirst[1] - legacyLast[4]);
    if (seamMin > 5) res.issues.push(`seam gap ${seamMin} min (expected 1)`);
    // relative tolerance: 5 ticks or 1 bp of price, whichever is larger (gold at ~$4000 needs bp scale)
    if (seamDev > Math.max(5 * tick, mirrorFirst[1] * 0.0001)) res.issues.push(`seam price jump ${seamDev} (> tolerance)`);
  }

  // per-year counts
  const perYear = {};
  for (const b of bars) {
    const y = new Date(b[0]).getUTCFullYear();
    perYear[y] = (perYear[y] || 0) + 1;
  }
  res.perYear = perYear;

  // outliers: top 1-min returns
  const moves = [];
  for (let i = 1; i < bars.length; i++) {
    const prev = bars[i - 1][4];
    if (prev > 0) {
      const ret = Math.abs(bars[i][4] - prev) / prev;
      if (ret > 0.01) moves.push([ret * 100, bars[i][0]]);
    }
  }
  moves.sort((a, b) => b[0] - a[0]);
  res.outliers = moves.slice(0, 5);

  res.barsArr = bars;
  return res;
}

function lcg(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

function pickTradingTs(rng, from, to) {
  for (let tries = 0; tries < 20; tries++) {
    const ts = Math.floor((from + rng() * (to - from)) / STEP) * STEP;
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
      if (res.status === 429) { await sleep(15000); continue; }
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
  const rng = lcg([...pair].reduce((a, ch) => a + ch.charCodeAt(0), 13));
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
      const ts = target + shiftTries * STEP;
      if (isWeekendBar(ts)) continue;
      let m1 = null;
      try { m1 = await fetchDayM1(cfg.code, ts); } catch (e) { /* keep null */ }
      if (!m1) { await sleep(400); continue; }
      const row = m1.find(r => r[0] === ts);
      await sleep(400);
      if (!row) continue;
      const ours = bars.find(b => b[0] === ts);
      if (!ours) continue;
      const maxDev = Math.max(
        Math.abs(ours[1] - row[1]), Math.abs(ours[2] - row[2]),
        Math.abs(ours[3] - row[3]), Math.abs(ours[4] - row[4])
      );
      const status = maxDev <= tick ? 'EXACT' : maxDev <= 2 * tick ? 'WARN' : 'FAIL';
      results.push({ ts, status, maxDev, official: row, ours });
      ok = true;
    }
    if (!ok) results.push({ ts: target, status: 'UNVERIFIED' });
  }
  return results;
}

/* ---------- main ---------- */
(async () => {
  log(`# M1 validation report - generated ${new Date().toISOString()}`);
  log(`# Files: m1-data/<pair>-m1-2024-09-11_2026-09-11.csv`);
  let overallFail = 0, overallWarn = 0;
  const persist = () => fs.writeFileSync(path.join(OUT_DIR, 'validation-report-m1.txt'), report.join('\n'), 'utf8');

  for (const [pair, cfg] of Object.entries(PAIRS)) {
    let res;
    try {
      res = analyzeFile(pair, cfg);
    } catch (e) {
      log(`\n## ${pair}: FATAL ${e.message}`);
      overallFail++;
      continue;
    }

    log(`\n## ${pair.toUpperCase()}`);
    log(`bars: ${res.bars} | coverage: ${iso(res.firstTs)} -> ${iso(res.lastTs)}`);
    log(`per-year: ${Object.entries(res.perYear).map(([y, n]) => `${y}:${n}`).join('  ')}`);
    let minC = Infinity, maxC = -Infinity;
    for (const b of res.barsArr) { if (b[4] < minC) minC = b[4]; if (b[4] > maxC) maxC = b[4]; }
    log(`close range: ${minC.toFixed(cfg.prec)} .. ${maxC.toFixed(cfg.prec)} | gaps: ${Object.entries(res.gapHist).filter(([, n]) => n).map(([k, n]) => `${k}=${n}`).join(', ')}`);
    log(`flat bars: ${res.flats} (longest run ${res.maxFlatRun}) | parse errors: ${res.parseErrors}`);

    if (res.topGaps.length) {
      log(`largest gaps: ${res.topGaps.map(g => `${g[0]}min (${iso(g[1])})`).join(' | ')}`);
    }

    log(`spot checks vs official Dukascopy API:`);
    const spots = await spotCheck(pair, cfg, res.barsArr, res.fsbStart);
    for (const s of spots) {
      if (s.status === 'UNVERIFIED') {
        log(`  UNVERIFIED ${iso(s.ts)} (API unavailable for that bar)`);
      } else {
        log(
          `  ${s.status.padEnd(9)} ${iso(s.ts)} | max deviation ${s.maxDev} | ours O ${s.ours[1]} H ${s.ours[2]} L ${s.ours[3]} C ${s.ours[4]}`
        );
        if (s.status === 'FAIL') res.issues.push(`spot check FAIL at ${iso(s.ts)} (dev ${s.maxDev})`);
        if (s.status === 'WARN') res.warns.push(`spot check small deviation at ${iso(s.ts)}`);
      }
    }

    if (res.outliers.length) {
      log(`>1% 1-min moves (review, likely news): ${res.outliers.map(m => `${m[0].toFixed(1)}% @ ${iso(m[1])}`).join(' | ')}`);
      for (const m of res.outliers) res.warns.push(`large 1-min move ${m[0].toFixed(1)}% at ${iso(m[1])}`);
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