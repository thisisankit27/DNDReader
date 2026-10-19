import AxeBuilder from '@axe-core/playwright';
import { test, expect, PAGES, stubDownloads, UA } from './fixtures';
import { ratio, rgb } from './contrast';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice'];
const SIZES = { desktop: { width: 1440, height: 900 }, mobile: { width: 390, height: 844 } };

async function reveal(page: any, path: string) {
  // Put the page in its busiest state: every disclosure open, the reader panel open, the JS-only notices
  // visible, a download started. Contrast and structure are then checked in all of them.
  await page.evaluate(() => {
    document.querySelectorAll('details').forEach((d: any) => (d.open = true));
    document.querySelectorAll('[data-arch-warn],[data-platform-mismatch],[data-distro-note],[data-suggest-guess]').forEach((e: any) => (e.hidden = false));
  });
  if (path === '') await page.locator('[data-reader-open]').click();
  const btn = page.locator('a[data-download]').first();
  if (await btn.count()) await Promise.all([page.waitForEvent('download').catch(() => {}), btn.click()]);
}

test.describe('axe: WCAG 2.2 A and AA, plus best practice', () => {
  // One test per page, scheme and size: a failure names its page, and no test can outrun its timeout.
  for (const scheme of ['light', 'dark'] as const) {
    for (const [sizeName, size] of Object.entries(SIZES)) {
      for (const p of PAGES) {
        test(`${scheme}, ${sizeName}, ${p || 'home'}: no violations, idle or fully revealed`, async ({ browser, sites }) => {
          test.setTimeout(120_000);
          const s = await sites('snap');
          const ctx = await browser.newContext({ viewport: size, colorScheme: scheme, userAgent: UA.windows });
          const page = await ctx.newPage();
          await stubDownloads(page);
          const failures: string[] = [];
          await page.goto(s.url(p));
          for (const state of ['idle', 'revealed']) {
            if (state === 'revealed') await reveal(page, p);
            const r = await new AxeBuilder({ page }).withTags(TAGS).analyze();
            for (const v of r.violations) failures.push(`[${state}] ${v.id} (${v.impact}): ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(' | ')}`);
          }
          expect(failures).toEqual([]);
          await ctx.close();
        });
      }
    }
  }

  test('the 404 page too', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('missing/'));
    const r = await new AxeBuilder({ page }).withTags(TAGS).analyze();
    expect(r.violations.map((v) => v.id)).toEqual([]);
  });
});

test.describe('structure', () => {
  test('one h1, no skipped heading levels, one of each landmark, a title, and a language', async ({ page, sites }) => {
    const s = await sites('snap');
    for (const p of PAGES) {
      await page.goto(s.url(p));
      const info = await page.evaluate(() => ({
        levels: [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].map((h) => Number(h.tagName[1])),
        banner: document.querySelectorAll('header.site-header').length,
        main: document.querySelectorAll('main').length,
        nav: document.querySelectorAll('nav').length,
        footer: document.querySelectorAll('footer').length,
        title: document.title,
        lang: document.documentElement.lang,
        viewport: document.querySelector('meta[name=viewport]')!.getAttribute('content'),
      }));
      expect(info.levels.filter((l) => l === 1), `${p}: h1 count`).toHaveLength(1);
      expect(info.levels[0], `${p}: starts at h1`).toBe(1);
      info.levels.forEach((l, i) => { if (i) expect(l - info.levels[i - 1], `${p}: heading jump at #${i} (${info.levels.join(',')})`).toBeLessThanOrEqual(1); });
      expect([info.banner, info.main, info.nav, info.footer], `${p}: landmarks`).toEqual([1, 1, 1, 1]);
      expect(info.title.length).toBeGreaterThan(10);
      expect(info.lang).toBe('en');
      expect(info.viewport).not.toMatch(/user-scalable\s*=\s*no|maximum-scale\s*=\s*1(\.0)?\b/);
    }
  });

  test('keyboard: every control is reachable, in a sensible order, with a visible focus ring', async ({ page, sites }) => {
    const s = await sites('snap');
    for (const p of PAGES) {
      await page.goto(s.url(p));
      await page.evaluate(() => document.querySelectorAll('details').forEach((d: any) => (d.open = true)));
      const expected = await page.evaluate(() =>
        [...document.querySelectorAll('a[href],button:not([hidden]):not([disabled]),select,summary')].filter((e: any) => e.offsetParent !== null || getComputedStyle(e).position === 'fixed').length,
      );
      const stops: { tag: string; ok: boolean; desc: string }[] = [];
      for (let i = 0; i < expected + 5; i++) {
        await page.keyboard.press('Tab');
        const r = await page.evaluate(() => {
          const e = document.activeElement as HTMLElement;
          if (!e || e === document.body) return null;
          const cs = getComputedStyle(e);
          return { tag: e.tagName, ok: cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) >= 2, desc: (e.textContent || e.getAttribute('aria-label') || '').trim().slice(0, 30) };
        });
        if (!r) break;
        stops.push(r);
      }
      const unringed = stops.filter((x) => !x.ok);
      expect(unringed, `${p}: focused elements without a visible ring`).toEqual([]);
      expect(stops.length, `${p}: tab stops vs interactive elements`).toBeGreaterThanOrEqual(expected - 1);
    }
  });

  test('the reader illustration is operable by keyboard: Enter opens, Escape closes and returns focus', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    const pill = page.locator('[data-reader-open]');
    await pill.focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('[data-reader]')).toHaveAttribute('data-open', '');
    await expect(pill).toHaveAttribute('aria-expanded', 'true');
    await expect(page.locator('[data-reader-title]')).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(page.locator('[data-reader]')).not.toHaveAttribute('data-open', /.*/);
    await expect(pill).toBeFocused();
    await expect(pill).toHaveAttribute('aria-expanded', 'false');
    await pill.focus();
    await page.keyboard.press('Control+e');
    await expect(page.locator('[data-reader]')).toHaveAttribute('data-open', '');
    await page.locator('[data-reader-close]').click();
    await expect(pill).toBeFocused();
  });

  test('prefers-reduced-motion: no transitions run', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto(s.url());
    const durations = await page.evaluate(() => ({
      panel: getComputedStyle(document.querySelector('.reader__panel')!).transitionDuration,
    }));
    expect(durations.panel).toBe('0s');
    await page.goto(s.url('download/ubuntu/'));
    expect(await page.evaluate(() => getComputedStyle(document.querySelector('.disclosure > summary')!, '::before').transitionDuration)).toBe('0s');
  });

  test('forced colours (Windows High Contrast): content stays readable and nothing overflows', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.emulateMedia({ forcedColors: 'active' });
    for (const p of PAGES) {
      await page.goto(s.url(p));
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
  });

  test('text spacing (WCAG 1.4.12) and 200% zoom reflow do not hide or clip content', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.setViewportSize({ width: 320, height: 640 }); // 1280 px at 400% zoom
    for (const p of PAGES) {
      await page.goto(s.url(p));
      await page.addStyleTag({ content: '*{line-height:1.5!important;letter-spacing:.12em!important;word-spacing:.16em!important} p{margin-bottom:2em!important}' });
      await page.evaluate(() => document.querySelectorAll('details').forEach((d: any) => (d.open = true)));
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), `${p}: horizontal scroll at 320 px with text spacing`).toBe(true);
      const clipped = await page.evaluate(() => [...document.querySelectorAll('.btn,.callout,.dlcard,.started,summary')].filter((e: any) => e.scrollHeight > e.clientHeight + 2 && getComputedStyle(e).overflow !== 'visible').map((e) => e.className));
      expect(clipped, `${p}: clipped boxes`).toEqual([]);
    }
  });
});

test.describe('colour contrast, measured from the real tokens', () => {
  const textPairs: [string, string, number][] = [
    ['--body', '--page', 4.5], ['--ink', '--page', 4.5], ['--muted', '--page', 4.5], ['--link', '--page', 4.5],
    ['--body', '--surface', 4.5], ['--muted', '--surface', 4.5], ['--link', '--surface', 4.5], ['--ink', '--surface', 4.5],
    ['--accent-text', '--page', 4.5], ['--on-primary', '--primary', 4.5], ['--on-accent', '--accent', 4.5],
    ['--on-hl', '--hl', 4.5], ['--body', '--code-bg', 4.5], ['--ink', '--code-bg', 4.5], ['--link', '--code-bg', 4.5], ['--muted', '--code-bg', 4.5],
    ['--ok', '--ok-tint', 4.5], ['--warn', '--warn-tint', 4.5], ['--danger', '--danger-tint', 4.5],
    ['--ok', '--page', 4.5], ['--warn', '--page', 4.5], ['--danger', '--page', 4.5],
    ['--body', '--paper', 4.5],
    // non-text: what defines a control must be 3:1 against what it sits on
    ['--control', '--page', 3], ['--control', '--surface', 3], ['--focus', '--page', 3], ['--focus', '--surface', 3],
  ];
  for (const scheme of ['light', 'dark'] as const) {
    test(`${scheme}: every text/background pair clears AA, every control border clears 3:1`, async ({ page, sites }) => {
      const s = await sites('snap');
      await page.emulateMedia({ colorScheme: scheme });
      await page.goto(s.url());
      const vars = await page.evaluate((names) => Object.fromEntries(names.map((n) => [n, getComputedStyle(document.documentElement).getPropertyValue(n).trim()])), [...new Set(textPairs.flat().filter((x) => typeof x === 'string'))] as string[]);
      const results = textPairs.map(([a, b, min]) => ({ pair: `${a} on ${b}`, r: +ratio(rgb(vars[a]), rgb(vars[b])).toFixed(2), min }));
      console.log(`CONTRAST ${scheme}: ` + results.map((x) => `${x.pair}=${x.r}`).join('  '));
      expect(results.filter((x) => x.r < x.min), `pairs below their minimum in ${scheme}`).toEqual([]);
    });
  }

  for (const scheme of ['light', 'dark'] as const) {
    test(`${scheme}: text over the hero's grid and glows still clears AA (sampled from real pixels)`, async ({ page, sites }) => {
      const s = await sites('snap');
      await page.emulateMedia({ colorScheme: scheme });
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(s.url());
      const targets = ['.hero h1', '.hero .lede', '.hero__note p', '.hero__note a', '.pun'];
      const out: string[] = [];
      for (const sel of targets) {
        const loc = page.locator(sel).first();
        if (!(await loc.count())) continue;
        const color = await loc.evaluate((e) => getComputedStyle(e).color);
        // Hide every glyph so only the lighting behind the text is photographed.
        const style = await page.addStyleTag({ content: '*{color:transparent!important;-webkit-text-fill-color:transparent!important;text-decoration-color:transparent!important;text-shadow:none!important}' });
        const png = (await loc.screenshot()).toString('base64');
        await style.evaluate((e) => e.remove());
        const worst = await page.evaluate(async ({ png, fg }) => {
          const img = new Image();
          img.src = 'data:image/png;base64,' + png;
          await img.decode();
          const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
          const g = c.getContext('2d')!; g.drawImage(img, 0, 0);
          const d = g.getImageData(0, 0, c.width, c.height).data;
          const L = (r: number, gg: number, b: number) => { const f = (v: number) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(gg) + 0.0722 * f(b); };
          const lf = L(fg[0], fg[1], fg[2]);
          let min = 99;
          for (let i = 0; i < d.length; i += 4) {
            const lb = L(d[i], d[i + 1], d[i + 2]);
            const [hi, lo] = lf > lb ? [lf, lb] : [lb, lf];
            min = Math.min(min, (hi + 0.05) / (lo + 0.05));
          }
          return min;
        }, { png, fg: rgb(color) });
        out.push(`${sel}=${worst.toFixed(2)}`);
        expect(worst, `${scheme}: ${sel} over the hero lighting`).toBeGreaterThanOrEqual(4.5);
      }
      console.log(`HERO-LIGHTING CONTRAST ${scheme} (worst pixel): ${out.join('  ')}`);
    });
  }
});
