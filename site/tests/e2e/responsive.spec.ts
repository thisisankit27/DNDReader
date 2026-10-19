import { test, expect, PAGES } from './fixtures';

const VIEWPORTS = [[320, 640], [390, 844], [768, 1024], [1024, 768], [1440, 900]] as const;

test.describe('responsive layouts', () => {
  for (const [w, h] of VIEWPORTS) {
    test(`${w}x${h}: no horizontal scroll, code wraps, controls are big enough`, async ({ page, sites }, info) => {
      const s = await sites('snap');
      await page.setViewportSize({ width: w, height: h });
      const small: string[] = [];
      for (const p of PAGES) {
        await page.goto(s.url(p));
        await page.evaluate(() => document.querySelectorAll('details').forEach((d: any) => (d.open = true)));
        const r = await page.evaluate(() => {
          const sw = document.documentElement.scrollWidth;
          const wide = [...document.querySelectorAll('body *')].filter((e) => { const b = e.getBoundingClientRect(); return b.width > 0 && b.right > innerWidth + 1 && !e.closest('.sr-only,.skip'); }).map((e) => e.tagName + '.' + e.className).slice(0, 5);
          const sideways = [...document.querySelectorAll('pre')].filter((e) => e.scrollWidth > e.clientWidth + 1).length;
          const targets = [...document.querySelectorAll('.btn, summary, select, button:not([hidden]), .site-nav a, .brand')]
            .filter((e: any) => e.offsetParent !== null)
            .map((e: any) => { const b = e.getBoundingClientRect(); return { n: (e.textContent || '').trim().slice(0, 24), w: Math.round(b.width), h: Math.round(b.height) }; });
          return { sw, iw: innerWidth, wide, sideways, targets };
        });
        expect(r.sw, `${p}: scrollWidth ${r.sw} > viewport ${r.iw}; overflowing: ${r.wide.join(', ')}`).toBeLessThanOrEqual(r.iw);
        expect(r.sideways, `${p}: code blocks that scroll sideways`).toBe(0);
        for (const t of r.targets) if (t.w < 24 || t.h < 24) small.push(`${p}: ${t.n} is ${t.w}x${t.h}`);
        await page.screenshot({ path: info.outputPath(`${p.replace(/\W/g, '') || 'home'}-${w}.png`), fullPage: true });
      }
      expect(small, 'controls under the 24 px WCAG 2.2 minimum').toEqual([]);
    });
  }

  test('targets are 44 px or more on a phone (reported, and enforced for the primary controls)', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.setViewportSize({ width: 390, height: 844 });
    for (const p of PAGES) {
      await page.goto(s.url(p));
      const under = await page.evaluate(() =>
        [...document.querySelectorAll('.btn, summary, select, .copy:not([hidden]), .site-nav a, .brand')].filter((e: any) => e.offsetParent !== null).map((e: any) => ({ n: (e.textContent || '').trim().slice(0, 24), h: Math.round(e.getBoundingClientRect().height) })).filter((t) => t.h < 44),
      );
      expect(under, `${p}: primary controls under 44 px tall`).toEqual([]);
    }
  });

  test('the hero reflows: copy then illustration on a phone, side by side on a desktop; the sheet is a bottom sheet on a phone', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(s.url());
    const a = await page.locator('.hero h1').boundingBox();
    const b = await page.locator('[data-reader]').boundingBox();
    expect(b!.y).toBeGreaterThan(a!.y + a!.height);
    await page.locator('[data-reader-open]').click();
    const panel = await page.locator('[data-reader-panel]').boundingBox();
    const reader = await page.locator('[data-reader]').boundingBox();
    expect(Math.abs(panel!.y + panel!.height - (reader!.y + reader!.height))).toBeLessThan(2); // docked to the bottom
    expect(panel!.width).toBeGreaterThan(reader!.width - 4);
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(s.url());
    const h = await page.locator('.hero h1').boundingBox();
    const r = await page.locator('[data-reader]').boundingBox();
    expect(r!.x).toBeGreaterThan(h!.x + h!.width - 5);
    await page.locator('[data-reader-open]').click();
    const p2 = await page.locator('[data-reader-panel]').boundingBox();
    const r2 = await page.locator('[data-reader]').boundingBox();
    expect(Math.abs(p2!.x + p2!.width - (r2!.x + r2!.width))).toBeLessThan(2); // docked to the right
  });
});
