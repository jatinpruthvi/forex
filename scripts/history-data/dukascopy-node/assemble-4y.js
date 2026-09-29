/* Assemble final 10-year m5 CSVs: legacy (2016-09-11 -> mirror start) + mirror (-> live). */
const fs = require('fs');
const path = require('path');

const BASE = path.join(__dirname, '..');
const OUT_DIR = path.join(BASE, 'm5-data');
const WINDOW_LABEL = `2016-09-11_${new Date().toISOString().slice(0, 10)}`;
const SEG_DIR = path.join(OUT_DIR, 'intermediates');
const PAIRS = [
  'eurusd', 'usdjpy', 'gbpusd', 'xauusd', 'eurgbp', 'eurjpy',
  'audusd', 'usdcad', 'nzdusd', 'usdchf', 'gbpjpy'
];

(async () => {
  for (const pair of PAIRS) {
    const legacyFile = path.join(SEG_DIR, `${pair}-m5-legacy.csv`);
    const mirrorFile = path.join(SEG_DIR, `${pair}-m5-fsb.csv`);
    if (!fs.existsSync(legacyFile)) {
      console.log(`SKIP ${pair} (no legacy file)`);
      continue;
    }

    const legacyLines = fs.readFileSync(legacyFile, 'utf8').trim().split('\n').slice(1);
    const mirrorLines = fs.readFileSync(mirrorFile, 'utf8').trim().split('\n').slice(1);

    const lastLegacyTs = +legacyLines[legacyLines.length - 1].split(',')[0];
    const firstMirrorTs = +mirrorLines[0].split(',')[0];
    const seamGapMin = (firstMirrorTs - lastLegacyTs) / 60000;

    const combined = [...legacyLines, ...mirrorLines];
    const outFile = path.join(OUT_DIR, `${pair}-m5-${WINDOW_LABEL}.csv`);
    fs.writeFileSync(outFile, 'timestamp,open,high,low,close,volume\n' + combined.join('\n') + '\n');

    console.log(
      `${pair}: ${combined.length} bars | legacy ends ${new Date(lastLegacyTs).toISOString()} | mirror starts ${new Date(
        firstMirrorTs
      ).toISOString()} | seam gap ${seamGapMin} min | ${outFile}`
    );
  }
})();
