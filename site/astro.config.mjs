// Base path is the classic way a Pages site ships broken. Everything that depends on where the site is
// served from comes from these two values, and nothing else in the project hard-codes a root path:
//
//   SITE_URL   origin the site is served from      (default: the project Pages origin)
//   SITE_BASE  path prefix on that origin          (default: /DNDReader ; use / on a custom domain)
//
// The custom-domain switch is therefore two repository variables and a re-run, not a code change.
// See site/README.md for the runbook.
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const site = (process.env.SITE_URL || 'https://thisisankit27.github.io').replace(/\/+$/, '');

function normaliseBase(raw) {
  if (raw === '/') return '/';
  return '/' + raw.replace(/^\/+|\/+$/g, '');
}
// An unset repository variable reaches the workflow as an empty string, which must mean "use the default".
// To serve from the root of a custom domain, set SITE_BASE to "/" explicitly.
const base = normaliseBase(process.env.SITE_BASE ? process.env.SITE_BASE : '/DNDReader');

export default defineConfig({
  site,
  base,
  // Tests build several variants (different release fixtures and base paths) side by side.
  outDir: process.env.OUT_DIR || './dist',
  trailingSlash: 'always',
  build: { format: 'directory' },
  compressHTML: true,
  // The Linux download is for Ubuntu 26.04 specifically, so the page is /download/ubuntu/. /download/linux/
  // is a small page of our own (src/pages/download/linux.astro), NOT an Astro `redirects` entry: that
  // writes its destination and canonical without the base path, which 404s on a project Pages site.
  integrations: [
    sitemap({ filter: (page) => !page.includes('/download/linux/') && !page.includes('/404') }),
  ],
});
