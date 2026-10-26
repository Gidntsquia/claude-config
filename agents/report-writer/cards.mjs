// Measures a report-writer page at 390 css px and, in phone mode, shoots one PNG per <section class="card">.
//
//   node cards.mjs <outdir> desktop|phone      (called by render.py; PLAYWRIGHT_DIR overrides the playwright install)
//
// Writes <outdir>/cards/measure.json: per card {index, slug, css_height_px, png, png_width_px, png_height_px, scale},
// per paragraph {card, text, lines}, ellipsis count, horizontal_scroll. Phone PNGs: <outdir>/cards/NN-<slug>.png at
// SCALE x device pixels (2x by default: 780 px wide for 390 css px, sharp on a phone). Exit 1 if playwright is missing.
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

const [outdir, mode = 'desktop', page_name = 'report.html'] = process.argv.slice(2);
if (!outdir) { console.error('usage: node cards.mjs <outdir> desktop|phone'); process.exit(2); }
const SCALE = +(process.env.CARD_SCALE ?? 2);
// Where playwright may be: $PLAYWRIGHT_DIR, ./node_modules, any project in the projects folder chosen at install
// ("projects" in ~/.claude/claude-config.json), then the global npm root.
const projectsDir = (() => {
  try { return JSON.parse(readFileSync(`${process.env.CLAUDE_CONFIG_DIR || `${process.env.HOME}/.claude`}/claude-config.json`, 'utf8')).projects; }
  catch { return null; }
})();
const inProjects = projectsDir && existsSync(projectsDir)
  ? readdirSync(projectsDir).map((d) => `${projectsDir}/${d}/node_modules/playwright`) : [];
const npmRoot = (() => { try { return execSync('npm root -g', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return null; } })();
const candidates = [process.env.PLAYWRIGHT_DIR, resolve(process.cwd(), 'node_modules/playwright'), ...inProjects,
  npmRoot && `${npmRoot}/playwright`].filter(Boolean);
const pwDir = candidates.find((d) => existsSync(d));
if (!pwDir) { console.error(`cards.mjs: playwright not found (looked in $PLAYWRIGHT_DIR, ./node_modules, ${projectsDir || 'the projects folder'}/*/node_modules, npm root -g); install it: npm i -g playwright && npx playwright install chromium`); process.exit(1); }
const { chromium } = createRequire(import.meta.url)(pwDir);

const dir = resolve(outdir, 'cards');
mkdirSync(dir, { recursive: true });
for (const f of readdirSync(dir)) if (/\.png$/.test(f)) unlinkSync(`${dir}/${f}`);
const page_path = resolve(outdir, page_name);
const html = readFileSync(page_path, 'utf8').replace(/<body data-mode="[^"]*"/, '<body data-mode="phone"');
const tmp = resolve(dir, 'phone-view.html');
writeFileSync(tmp, html);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: SCALE });
await page.goto(`file://${tmp}`);
await page.waitForLoadState('load');
await page.evaluate(() => { for (const d of document.querySelectorAll('details')) d.open = true; });
const info = await page.evaluate(() => {
  const cards = [...document.querySelectorAll('section.card')].map((c, i) => ({ index: i + 1, slug: c.id, css_height_px: Math.ceil(c.getBoundingClientRect().height) }));
  const lineHeight = (el) => { const lh = parseFloat(getComputedStyle(el).lineHeight); return isNaN(lh) ? parseFloat(getComputedStyle(el).fontSize) * 1.4 : lh; };
  const paragraphs = [...document.querySelectorAll('section.card p:not(.question), section.card li')].map((p) => {
    const card = p.closest('section.card');
    // a quoted ask is the user's own words: only the "why" line after it is the writer's prose; an Evidence item is a
    // claim plus reference rows: only the claim is prose
    const m = (p.matches('.problem.quoted') && p.querySelector('.why')) || (p.closest('#evidence') && p.querySelector('.claim')) || p;
    const r = m.getBoundingClientRect();
    const box = p.closest('#wrong-or-missing') ? 'wrong-or-missing' : (p.id || '');
    return { card: card ? card.id : '', box, text: m.textContent.trim().slice(0, 80), lines: Math.round(r.height / lineHeight(m)) };
  });
  const text = document.body.innerText;
  const ellipsis = (text.match(/…/g) ?? []).length + (text.match(/\.\.\./g) ?? []).length;
  const horizontal_scroll = document.documentElement.scrollWidth > document.documentElement.clientWidth + 1;
  // text past its box: any element whose scrollWidth exceeds its clientWidth and that is not a scroll container
  const overflow = [...document.querySelectorAll('p, li, td, th, h1, h2, figcaption')].filter((e) => e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflowX !== 'auto').map((e) => e.textContent.trim().slice(0, 60));
  // first screen: how far down the page (css px from the top) the last first-screen element ends
  const bottom = (sel) => { const e = document.querySelector(sel); return e ? Math.ceil(e.getBoundingClientRect().bottom + window.scrollY) : null; };
  // only what is on card 1 counts; blocks the report moved to the "The numbers" card (first.move_down) are listed as moved
  const fsel = { problem: '#problem', verdict: '#verdict', points: '#points', next_action: '#next-action', deciding: '#deciding', wrong_or_missing: '#wrong-or-missing', decision_chart: '#decision-chart', decision_table: '#decision-table' };
  const first_screen = {};
  const moved = [];
  for (const [k, sel] of Object.entries(fsel)) {
    if (k === 'points' && !document.querySelector(sel)) continue;  // main points are optional
    if (document.querySelector('#numbers ' + sel)) { moved.push(k); continue; }
    first_screen[k] = bottom(sel);
  }
  first_screen.bottom_px = Math.max(...Object.values(first_screen).filter((v) => v !== null));
  first_screen.moved = moved;
  return { cards, paragraphs, ellipsis, horizontal_scroll, overflow, first_screen };
});
// the same page as the user sees it in desktop mode, in a 1530 x 1250 css px window (Firefox at 1530 x 1400 minus chrome)
const dpage = await browser.newPage({ viewport: { width: 1530, height: 1250 } });
await dpage.goto(`file://${page_path}`);
await dpage.waitForLoadState('load');
const desktop_first_screen = await dpage.evaluate(() => {
  const bottom = (sel) => { const e = document.querySelector(sel); return e ? Math.ceil(e.getBoundingClientRect().bottom + window.scrollY) : null; };
  const o = {};
  for (const [k, sel] of Object.entries({ problem: '#problem', verdict: '#verdict', points: '#points', next_action: '#next-action', deciding: '#deciding', wrong_or_missing: '#wrong-or-missing', decision_chart: '#decision-chart', decision_table: '#decision-table' })) {
    if (k === 'points' && !document.querySelector(sel)) continue;
    if (!document.querySelector('#numbers ' + sel)) o[k] = bottom(sel);
  }
  o.bottom_px = Math.max(...Object.values(o).filter((v) => v !== null));
  o.viewport_px = 1250;
  return o;
});
await dpage.close();
info.desktop_first_screen = desktop_first_screen;

const out = { mode, scale: SCALE, css_width_px: 390, phone_viewport_px: 844, ...info };
if (mode === 'phone') {
  const sections = await page.$$('section.card');
  for (let i = 0; i < sections.length; i++) {
    const slug = info.cards[i].slug;
    const name = `${String(i + 1).padStart(2, '0')}-${slug}.png`;
    await sections[i].screenshot({ path: `${dir}/${name}` });
    const buf = readFileSync(`${dir}/${name}`);
    out.cards[i].png = `cards/${name}`;
    out.cards[i].png_width_px = buf.readUInt32BE(16);
    out.cards[i].png_height_px = buf.readUInt32BE(20);
  }
}
await browser.close();
unlinkSync(tmp);
writeFileSync(resolve(dir, 'measure.json'), JSON.stringify(out, null, 1));
const tall = out.cards.filter((c) => c.css_height_px > 1500).length;
const long = out.paragraphs.filter((p) => p.lines > 3).length;
console.log(`cards.mjs: first screen ends at ${out.first_screen.bottom_px} css px of 844 on the phone, ${out.desktop_first_screen.bottom_px} of 1250 on the desktop; ${out.cards.length} cards at 390 css px (${SCALE}x), ${tall} over 1500 css px tall, ${long} paragraphs over 3 lines, ${out.ellipsis} ellipses, horizontal scroll ${out.horizontal_scroll ? 'YES' : 'no'}, ${out.overflow.length} overflowing boxes${mode === 'phone' ? `, PNGs in ${dir}` : ''}`);
