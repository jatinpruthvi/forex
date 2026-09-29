/* Backwards-compatible entry point: run the resumable, rate-limit-aware job. */
const { spawnSync } = require('child_process');
const path = require('path');

const downloader = path.join(__dirname, 'run-chunked-m5.js');
const result = spawnSync(process.execPath, [downloader], {
  env: process.env,
  stdio: 'inherit'
});

if (result.error) {
  console.error(`Could not start the M5 downloader: ${result.error.message}`);
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
