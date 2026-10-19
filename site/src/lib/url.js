// The only place a site path becomes a URL. Components never write a literal "/..." href.
const BASE = import.meta.env.BASE_URL; // "/DNDReader/" or "/", always ends with "/"
const SITE = import.meta.env.SITE; // origin, no trailing slash

/** Path inside the site, honouring the base: url('download/android/') -> "/DNDReader/download/android/". */
export function url(path = '') {
  return BASE + String(path).replace(/^\/+/, '');
}

/** Absolute URL, for canonical links, Open Graph and the sitemap. */
export function absolute(path = '') {
  return SITE + url(path);
}
