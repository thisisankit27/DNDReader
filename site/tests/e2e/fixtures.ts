import { test as base, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serve } from './server.mjs';
import { VARIANTS } from './variants.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const OUT = resolve(root, '.build-out');

export interface Site {
  name: string;
  dir: string;
  base: string; // '/DNDReader/' or '/'
  origin: string;
  /** Full URL of a path inside the site: site.url('download/') */
  url: (path?: string) => string;
  /** The release data this variant was built from. */
  data: any;
}

type Sites = (name: string) => Promise<Site>;

export const test = base.extend<{}, { sites: Sites }>({
  sites: [
    async ({}, use) => {
      const started = new Map<string, { site: Site; close: () => Promise<void> }>();
      await use(async (name: string) => {
        const hit = started.get(name);
        if (hit) return hit.site;
        const v = (VARIANTS as any)[name];
        if (!v) throw new Error(`unknown variant ${name}`);
        const dir = resolve(OUT, name);
        const s = await serve(dir, v.base);
        const base = v.base === '/' ? '/' : v.base.replace(/\/?$/, '/');
        const site: Site = {
          name, dir, base, origin: s.origin,
          url: (p = '') => `${s.origin}${base}${p.replace(/^\//, '')}`,
          data: JSON.parse(readFileSync(resolve(OUT, `${name}.releases.json`), 'utf8')),
        };
        started.set(name, { site, close: s.close });
        return site;
      });
      for (const { close } of started.values()) await close();
    },
    { scope: 'worker' },
  ],
});
export { expect };

export const UA = {
  windows: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
  windowsFirefox: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0',
  android: 'Mozilla/5.0 (Linux; Android 12; moto g60) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36',
  ubuntu: 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0',
  linux: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
  mac: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15',
  iphone: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
  chromeos: 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
};

export const PAGES = ['', 'download/', 'download/ubuntu/', 'download/windows/', 'download/android/', 'how-it-works/'];

/** Stub every GitHub release-asset download so tests never hit the network and the body is tiny. */
export async function stubDownloads(page: import('@playwright/test').Page) {
  await page.route('https://github.com/thisisankit27/DNDReader/releases/download/**', (route) => {
    const name = decodeURIComponent(new URL(route.request().url()).pathname.split('/').pop()!);
    return route.fulfill({
      status: 200,
      headers: { 'content-disposition': `attachment; filename=${name}`, 'content-type': 'application/octet-stream' },
      body: 'stub',
    });
  });
}
