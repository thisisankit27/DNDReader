import { test, expect, PAGES } from './fixtures';

test.describe('SEO', () => {
  test('unique titles and descriptions, sensible lengths, canonical, Open Graph, Twitter card', async ({ page, request, sites }) => {
    const s = await sites('snap');
    const titles = new Set<string>(), descs = new Set<string>();
    for (const p of PAGES) {
      await page.goto(s.url(p));
      const m = await page.evaluate(() => {
        const q = (sel: string, attr: string) => document.querySelector(sel)?.getAttribute(attr) ?? '';
        return {
          title: document.title, desc: q('meta[name=description]', 'content'), canonical: q('link[rel=canonical]', 'href'),
          ogTitle: q('meta[property="og:title"]', 'content'), ogDesc: q('meta[property="og:description"]', 'content'),
          ogImage: q('meta[property="og:image"]', 'content'), ogUrl: q('meta[property="og:url"]', 'content'), ogType: q('meta[property="og:type"]', 'content'),
          tw: q('meta[name="twitter:card"]', 'content'), robots: q('meta[name=robots]', 'content'), icon: q('link[rel=icon]', 'href'),
        };
      });
      expect(m.title.length, `${p}: title length`).toBeGreaterThan(15);
      expect(m.title.length, `${p}: title length`).toBeLessThanOrEqual(75);
      expect(m.desc.length, `${p}: description length`).toBeGreaterThanOrEqual(60);
      expect(m.desc.length, `${p}: description length`).toBeLessThanOrEqual(175);
      expect(titles.has(m.title), `${p}: duplicate title`).toBe(false);
      expect(descs.has(m.desc), `${p}: duplicate description`).toBe(false);
      titles.add(m.title); descs.add(m.desc);
      expect(m.ogTitle).toBe(m.title);
      expect(m.ogDesc).toBe(m.desc);
      expect(m.ogUrl).toBe(m.canonical);
      expect(m.ogType).toBe('website');
      expect(m.tw).toBe('summary_large_image');
      expect(m.robots, `${p}: indexable`).toBe('');
      expect(m.canonical).toMatch(/^https:\/\/thisisankit27\.github\.io\/DNDReader\//);
      const img = new URL(m.ogImage);
      const r = await request.get(s.origin + img.pathname);
      expect(r.status(), `${p}: og:image resolves`).toBe(200);
      expect(r.headers()['content-type']).toBe('image/png');
      expect((await r.body()).length).toBeGreaterThan(5_000);
    }
  });

  test('titles say what the page is, with the version where it matters', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/android/'));
    await expect(page).toHaveTitle('Download DNDReader for Android, version 0.3.0');
    await page.goto(s.url('download/'));
    await expect(page).toHaveTitle('Download DNDReader 0.3.0 for Ubuntu, Windows or Android');
  });

  test('JSON-LD is valid, accurate, and carries no ratings, counts or prices', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    const raw = await page.locator('script[type="application/ld+json"]').textContent();
    const j = JSON.parse(raw!);
    expect(j['@type']).toBe('SoftwareApplication');
    expect(j.name).toBe('DNDReader');
    expect(j.softwareVersion).toBe('0.3.0');
    expect(j.license).toBe('https://www.apache.org/licenses/LICENSE-2.0');
    expect(j.operatingSystem).toBe('Ubuntu, Windows, Android');
    for (const k of ['aggregateRating', 'review', 'offers', 'ratingValue', 'interactionStatistic', 'downloadUrl']) expect(j).not.toHaveProperty(k);
  });

  test('the 404 page and the Linux stub are noindex; the sitemap lists exactly the indexable pages', async ({ page, request, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('missing/'));
    await expect(page.locator('meta[name=robots]')).toHaveAttribute('content', 'noindex');
    await page.goto(s.url('download/linux/'));
    await page.waitForURL(s.url('download/ubuntu/'));
    const stub = (await request.get(s.url('download/linux/'))).status();
    expect(stub).toBe(200);
    const idx = await (await request.get(s.url('sitemap-index.xml'))).text();
    expect(idx).toContain('/DNDReader/sitemap-0.xml');
    const sm = await (await request.get(s.url('sitemap-0.xml'))).text();
    const locs = [...sm.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    expect(locs.sort()).toEqual(PAGES.map((p) => `https://thisisankit27.github.io/DNDReader/${p}`).sort());
  });

  test('exactly one h1 per page, and it matches what the page is about', async ({ page, sites }) => {
    const s = await sites('snap');
    const want: Record<string, string> = {
      '': 'Look it up without losing your place.', 'download/': 'Download DNDReader', 'download/ubuntu/': 'DNDReader for Ubuntu',
      'download/windows/': 'DNDReader for Windows', 'download/android/': 'DNDReader for Android', 'how-it-works/': 'How it works',
    };
    for (const p of PAGES) {
      await page.goto(s.url(p));
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(want[p]);
    }
  });
});
