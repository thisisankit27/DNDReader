import { test, expect, PAGES } from './fixtures';

// Budgets are commitments (gzip, as Pages serves text). A miss is reported with its number and is never
// re-baselined here: see the plan, section 9.
const BUDGET = { htmlKB: 20, cssKB: 20, jsKB: { home: 10, other: 6 }, fontsKB: 90, lcpMs: 1500, cls: 0.02, tbtMs: 50, inpMs: 100 };

test.describe('performance budget (Chromium only: it needs DevTools throttling)', () => {
  test.skip(({ browserName }) => browserName !== 'chromium', 'uses CDP throttling');

  for (const [vpName, vp] of [['desktop', { width: 1440, height: 900 }], ['phone', { width: 390, height: 844 }]] as const)
  for (const p of PAGES) {
    test(`${p || 'home'} (${vpName}): transfer sizes, Core Web Vitals under 4x CPU and a 1.6 Mbps / 150 ms network`, async ({ page, sites }) => {
      const s = await sites('snap');
      await page.setViewportSize(vp);
      const client = await page.context().newCDPSession(page);
      await client.send('Network.enable');
      await client.send('Network.emulateNetworkConditions', { offline: false, latency: 150, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 });
      await client.send('Emulation.setCPUThrottlingRate', { rate: 4 });

      const types = new Map<string, string>();
      const bytes: Record<string, number> = { Document: 0, Stylesheet: 0, Script: 0, Font: 0, Image: 0, Other: 0 };
      client.on('Network.responseReceived', (e: any) => types.set(e.requestId, e.type));
      client.on('Network.loadingFinished', (e: any) => {
        const t = types.get(e.requestId) ?? 'Other';
        bytes[t in bytes ? t : 'Other'] += e.encodedDataLength;
      });

      await page.addInitScript(() => {
        const w = window as any;
        w.__m = { lcp: 0, cls: 0, tbt: 0, inp: 0, fcp: 0, preFcpTask: 0 };
        const tasks: [number, number][] = [];
        w.__tasks = tasks;
        new PerformanceObserver((l) => { for (const e of l.getEntries()) if (e.name === 'first-contentful-paint') w.__m.fcp = e.startTime; }).observe({ type: 'paint', buffered: true });
        new PerformanceObserver((l) => { for (const e of l.getEntries()) w.__m.lcp = e.startTime; }).observe({ type: 'largest-contentful-paint', buffered: true });
        new PerformanceObserver((l) => { for (const e of l.getEntries() as any[]) if (!e.hadRecentInput) w.__m.cls += e.value; }).observe({ type: 'layout-shift', buffered: true });
        new PerformanceObserver((l) => { for (const e of l.getEntries()) tasks.push([e.startTime, e.duration]); }).observe({ type: 'longtask', buffered: true });
        new PerformanceObserver((l) => { for (const e of l.getEntries() as any[]) if (e.interactionId) w.__m.inp = Math.max(w.__m.inp, e.duration); }).observe({ type: 'event', durationThreshold: 16, buffered: true } as any);
      });
      const RUNS = 3; // worst of three loads: a shift that depends on timing must not hide behind a lucky run
      let m: any;
      const worstOf: any = { lcp: 0, cls: 0, tbt: 0, inp: 0, fcp: 0, preFcpTask: 0 };
      for (let run = 0; run < RUNS; run++) {
      for (const k of Object.keys(bytes)) bytes[k] = 0;
      await page.goto(s.url(p), { waitUntil: 'networkidle' });
      await page.waitForTimeout(500);
      if (p === '') { await page.locator('[data-reader-open]').click(); await page.waitForTimeout(400); }
      // TBT as Lighthouse defines it: blocking time (duration over 50 ms) of long tasks AFTER First Contentful
      // Paint. The one-off first style/layout pass before first paint is reported separately, not hidden.
      m = await page.evaluate(() => {
        const w = window as any;
        for (const [start, dur] of w.__tasks as [number, number][]) {
          if (start >= w.__m.fcp) w.__m.tbt += Math.max(0, dur - 50);
          else w.__m.preFcpTask = Math.max(w.__m.preFcpTask, dur);
        }
        return w.__m;
      });
      for (const k of Object.keys(worstOf)) worstOf[k] = Math.max(worstOf[k], m[k]);
      }
      Object.assign(m, worstOf);
      const kb = (n: number) => +(n / 1024).toFixed(1);
      const isHome = p === '';
      const line = `PERF ${p || 'home'} [${vpName}]: html=${kb(bytes.Document)}KB css=${kb(bytes.Stylesheet)}KB js=${kb(bytes.Script)}KB fonts=${kb(bytes.Font)}KB img=${kb(bytes.Image)}KB total=${kb(Object.values(bytes).reduce((a, b) => a + b, 0))}KB | LCP=${Math.round(m.lcp)}ms CLS=${m.cls.toFixed(4)} TBT=${Math.round(m.tbt)}ms (pre-FCP first-layout task ${Math.round(m.preFcpTask)}ms, FCP ${Math.round(m.fcp)}ms) INP~${Math.round(m.inp)}ms`;
      console.log(line);
      test.info().annotations.push({ type: 'perf', description: line });

      expect.soft(kb(bytes.Document), 'html').toBeLessThanOrEqual(BUDGET.htmlKB);
      expect.soft(kb(bytes.Stylesheet), 'css').toBeLessThanOrEqual(BUDGET.cssKB);
      expect.soft(kb(bytes.Script), 'js').toBeLessThanOrEqual(isHome ? BUDGET.jsKB.home : BUDGET.jsKB.other);
      expect.soft(kb(bytes.Font), 'fonts').toBeLessThanOrEqual(BUDGET.fontsKB);
      expect.soft(bytes.Image, 'no raster images on the page').toBe(0);
      expect.soft(m.lcp, 'LCP').toBeLessThanOrEqual(BUDGET.lcpMs);
      expect.soft(m.cls, 'CLS').toBeLessThanOrEqual(BUDGET.cls);
      expect.soft(m.tbt, 'TBT').toBeLessThanOrEqual(BUDGET.tbtMs);
      expect.soft(m.inp, 'interaction latency (INP proxy)').toBeLessThanOrEqual(BUDGET.inpMs);
    });
  }

  test('only two font files exist and both are Latin-subset woff2', async ({ sites }) => {
    const s = await sites('snap');
    const fs = await import('node:fs');
    const files = fs.readdirSync(`${s.dir}/_astro`).filter((f) => f.endsWith('.woff2'));
    expect(files).toHaveLength(2);
    const total = files.reduce((n, f) => n + fs.statSync(`${s.dir}/_astro/${f}`).size, 0);
    expect(total / 1024).toBeLessThanOrEqual(BUDGET.fontsKB);
  });

  test('the sans font is preloaded and nothing else is', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    const pre = await page.locator('link[rel=preload]').evaluateAll((els) => els.map((e) => e.getAttribute('href')));
    expect(pre).toHaveLength(1);
    expect(pre[0]).toMatch(/atkinson-hyperlegible-next.*\.woff2$/);
  });
});
