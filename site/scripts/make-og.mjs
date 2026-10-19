// Regenerates public/og.png (1200x630) from the project's own icon and type. Committed, not built, so a
// normal build needs no browser: run `node scripts/make-og.mjs` only if the headline or identity changes.
import { chromium } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const font = readFileSync(resolve(root, 'src/assets/fonts/atkinson-hyperlegible-next-latin-wght-normal.woff2')).toString('base64');
const icon = readFileSync(resolve(root, 'src/assets/icon.svg'), 'utf8');
const html = `<!doctype html><meta charset="utf-8"><style>
@font-face{font-family:A;src:url(data:font/woff2;base64,${font}) format('woff2-variations');font-weight:200 800}
*{box-sizing:border-box;margin:0}
body{width:1200px;height:630px;background:#0e1726;color:#f1f4f9;font-family:A,system-ui,sans-serif;display:flex;flex-direction:column;justify-content:center;padding:0 96px;gap:40px}
.brand{display:flex;align-items:center;gap:24px;font-size:44px;font-weight:700}
.brand svg{width:84px;height:84px;border-radius:18px}
h1{font-size:92px;line-height:1.04;letter-spacing:-0.025em;font-weight:700;max-width:960px}
p{font-size:30px;color:#9fb0c7;white-space:nowrap}
.bar{position:absolute;left:0;top:0;bottom:0;width:20px;background:#f09a58}
</style><div class="bar"></div><div class="brand">${icon}<span>DNDReader</span></div><h1>Look it up without losing your place.</h1><p>A small, open-source PDF reader for Ubuntu, Windows and Android.</p>`;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
await page.setContent(html);
await page.evaluate(() => document.fonts.ready);
writeFileSync(resolve(root, 'public/og.png'), await page.screenshot({ type: 'png' }));
await browser.close();
console.log('wrote public/og.png');
