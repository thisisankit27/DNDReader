import { test, expect, PAGES } from './fixtures';

// The classic Pages failure is a site that works at / and breaks under /<repo>/. The server only serves
// under the base, so any root-absolute link or asset really 404s here.
for (const name of ['snap', 'snap-root']) {
  test.describe(`base path: ${name}`, () => {
    test('every internal link, script, stylesheet, font, icon and image resolves (200)', async ({ page, request, sites }) => {
      const s = await sites(name);
      const seen = new Set<string>();
      const queue = [s.url()];
      const bad: string[] = [];
      const leaks: string[] = [];
      while (queue.length) {
        const u = queue.shift()!;
        if (seen.has(u)) continue;
        seen.add(u);
        const res = await page.goto(u);
        if (res!.status() !== 200 && !u.endsWith('/404/')) bad.push(`${res!.status()} ${u}`);
        const refs: string[] = await page.evaluate(() =>
          [...document.querySelectorAll('a[href],link[href],script[src],img[src],source[src]')].map(
            (e) => (e.getAttribute('href') ?? e.getAttribute('src'))!,
          ),
        );
        for (const r of refs) {
          if (/^(https?:|mailto:|#|data:)/.test(r)) continue;
          // Everything internal must start with the base, never a bare "/".
          if (s.base !== '/' && r.startsWith('/') && !r.startsWith(s.base)) leaks.push(`${u} -> ${r}`);
          const abs = new URL(r, u).href.split('#')[0];
          if (!abs.startsWith(s.origin)) continue;
          if (/\.(html)?$|\/$/.test(abs) && !abs.endsWith('.html')) queue.push(abs);
          else {
            const rr = await request.get(abs);
            if (rr.status() !== 200) bad.push(`${rr.status()} ${abs} (from ${u})`);
          }
        }
      }
      expect(leaks, `root-absolute links that would break under ${s.base}`).toEqual([]);
      expect(bad).toEqual([]);
      expect(seen.size).toBeGreaterThanOrEqual(PAGES.length);
    });

    test('canonical, Open Graph, sitemap and robots all follow the configured origin and base', async ({ page, request, sites }) => {
      const s = await sites(name);
      const origin = name === 'snap-root' ? 'https://dndreader.example' : 'https://thisisankit27.github.io';
      for (const p of PAGES) {
        await page.goto(s.url(p));
        await expect(page.locator('link[rel=canonical]')).toHaveAttribute('href', `${origin}${s.base}${p}`);
        await expect(page.locator('meta[property="og:url"]')).toHaveAttribute('content', `${origin}${s.base}${p}`);
        await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', `${origin}${s.base}og.png`);
      }
      const sm = await (await request.get(s.url('sitemap-0.xml'))).text();
      for (const p of PAGES) expect(sm).toContain(`<loc>${origin}${s.base}${p}</loc>`);
      expect(sm).not.toContain('/download/linux/');
      const robots = await (await request.get(s.url('robots.txt'))).text();
      expect(robots).toContain(`Sitemap: ${origin}${s.base}sitemap-index.xml`);
    });

    test('nothing at the server root answers (so a leaked root path fails here, not in production)', async ({ request, sites }) => {
      const s = await sites(name);
      if (s.base === '/') return;
      expect((await request.get(`${s.origin}/download/`)).status()).toBe(404);
      expect((await request.get(`${s.origin}/_astro/`)).status()).toBe(404);
    });
  });
}
