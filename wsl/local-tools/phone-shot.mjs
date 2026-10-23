// Phone picture of a page: full-page PNG at 390 css px wide, device scale 2 (780 px wide), split into numbered parts
// when the page is taller than three phone screens (3 x 844 = 2532 css px).
//   node phone-shot.mjs <out-base> <url>        -> <out-base>.png, or <out-base>-p1.png, -p2.png ... ; prints "png <path> WxH" per part
// Playwright is found like report-writer/cards.mjs: PLAYWRIGHT_DIR, ./node_modules/playwright, then the two known installs.
import { createRequire } from 'node:module';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const [base, url] = process.argv.slice(2);
if (!base || !url) { console.error('usage: node phone-shot.mjs <out-base> <url>'); process.exit(2); }
const candidates = [process.env.PLAYWRIGHT_DIR, resolve(process.cwd(), 'node_modules/playwright'),
  `${process.env.HOME}/files/workout-visualizer/node_modules/playwright`, `${process.env.HOME}/files/pogo-gbl-team-generator/node_modules/playwright`].filter(Boolean);
const pwDir = candidates.find((d) => existsSync(d));
if (!pwDir) { console.error(`phone-shot.mjs: playwright not found (tried ${candidates.join(', ')}); set PLAYWRIGHT_DIR`); process.exit(1); }
const { chromium } = createRequire(import.meta.url)(pwDir);
const W = 390, SCREEN = 844, MAX = 3 * SCREEN, SCALE = +(process.env.PHONE_SCALE ?? 2);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: SCREEN }, deviceScaleFactor: SCALE });
await page.goto(url, { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(+(process.env.PHONE_SETTLE_MS ?? 500));
const height = await page.evaluate(() => Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, 1));
await page.setViewportSize({ width: W, height: Math.max(120, Math.min(SCREEN, height)) });  // short content: no blank tail
const size = (p) => { const b = readFileSync(p); return `${b.readUInt32BE(16)}x${b.readUInt32BE(20)}`; };
if (height <= MAX) {
  const out = `${base}.png`;
  await page.screenshot({ path: out, fullPage: true });
  console.log(`png ${out} ${size(out)}`);
} else {
  let n = 0;
  for (let y = 0; y < height; y += MAX) {
    const out = `${base}-p${++n}.png`;
    await page.screenshot({ path: out, fullPage: true, clip: { x: 0, y, width: W, height: Math.min(MAX, height - y) } });
    console.log(`png ${out} ${size(out)}`);
  }
}
await browser.close();
