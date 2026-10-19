import type { APIRoute } from 'astro';
import { absolute } from '../lib/url.js';

// Crawlers only read robots.txt at a host's root, so on the project URL (.../DNDReader/) this is inert;
// it starts to matter the day the custom domain is attached. It costs nothing to ship now.
export const GET: APIRoute = () =>
  new Response(`User-agent: *\nAllow: /\n\nSitemap: ${absolute('sitemap-index.xml')}\n`, {
    headers: { 'content-type': 'text/plain; charset=utf-8' },
  });
