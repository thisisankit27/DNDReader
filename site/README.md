# DNDReader site

The landing and download site, deployed to GitHub Pages by `.github/workflows/site.yml`. Static HTML
(Astro 7), one stylesheet, about 2 KB of JavaScript. Nothing here touches the app: this directory and the
workflow are the only things the site work changes.

```bash
cd site
npm ci
npm run dev            # fetches release data, then serves at http://localhost:4321/DNDReader/
npm run build          # fetch release data, check the signing pin, build into dist/
npm test               # unit tests, then Playwright + axe (builds every variant it needs)
```

Node 22 or newer (Astro 7 needs 22.22+). `npx playwright install chromium firefox webkit` once for the browser
tests (WebKit needs system libraries on Linux; CI installs them with `--with-deps`).

## Where release data comes from

Nothing about a release is typed into a page. `scripts/fetch-releases.mjs` reads the GitHub Releases API
at build time and writes `src/data/releases.generated.json` (git-ignored):

| Status | When | What the site does |
|---|---|---|
| `ok` | releases found | renders version, size, file name, checksum and links from the data |
| `no-releases` | nothing publishable | says "No release is published yet", offers no download |
| `unavailable` | rate limit, 5xx, offline | **still builds**, with no version/size/checksum anywhere and one link to the release page; **the deploy is skipped** so the last good site stays live |

A release file is recognised by one table, `ASSET_RULES` in `src/lib/releases.mjs`. A new release of the same
files needs no change. A new platform is one rule plus its page.

**Integrity problems stop the build** (they are bugs or incidents, never outages): a checksum in the API that
disagrees with the release notes; a file named for another version; a download URL that is not this
repository's release path; a malformed size or digest. And `npm run check:pin` fails if the Android signing
fingerprint in `src/data/signing-key.json` disagrees with `EXPECTED_CERT_SHA256` in `android-release.yml` or
with the fingerprint printed in the release notes. **Do not edit one value to match another: investigate.**

The site makes no runtime calls to GitHub from a visitor's browser, so visiting it sends nobody's address to
api.github.com. The cost is that a new release shows up when the site is rebuilt: the workflow does that on
every release event (a few minutes), plus weekly as a safety net.

## Base path, and the custom-domain switch

All links and assets go through `url()` in `src/lib/url.js`; no component writes a literal `/` path. Two
values control everything (`astro.config.mjs`):

| | Project site (today) | Custom domain |
|---|---|---|
| `SITE_URL` | `https://thisisankit27.github.io` (default) | `https://<your-domain>` |
| `SITE_BASE` | `/DNDReader` (default) | `/` |

The test suite builds and crawls **both** configurations, and its server only answers under the base path, so a
root-absolute link fails the tests rather than production.

**Switching to a custom domain** (no code change; the redirects at GitHub keep old links working, which is
documented behaviour and worth confirming once):

1. At your DNS provider add GitHub Pages' records for the domain (apex A/AAAA, or a CNAME for `www`). This is
   harmless on its own.
2. Repository **Settings → Secrets and variables → Actions → Variables**: set `SITE_URL` and `SITE_BASE=/`.
3. Straight away: **Settings → Pages → Custom domain**, enter the domain, save. Re-run the `site` workflow if it
   did not run on its own. There is a window of a few minutes between 2 and 3 in which the old URL's assets
   point at the new base; do them back to back.
4. Wait for the DNS check and certificate, then tick **Enforce HTTPS**.
5. Update the repository's Website field (About) to the new address.

A `CNAME` file is not needed: with Actions publishing, GitHub ignores it and keeps the domain in settings.
`robots.txt` and the sitemap already follow `SITE_URL`.

## Going live the first time

1. Merge the branch. 2. Enable Pages with the workflow as source:
`gh api -X POST repos/thisisankit27/DNDReader/pages -f build_type=workflow` (or Settings → Pages → Source:
GitHub Actions). 3. Run the `site` workflow (or push). 4. When
`https://thisisankit27.github.io/DNDReader/` answers 200, set About:

```bash
gh repo edit thisisankit27/DNDReader \
  --description "A small, open-source PDF reader: select text, choose Find meaning, and search results open beside the page. Close them and you are back where you were. Ubuntu, Windows, Android." \
  --homepage "https://thisisankit27.github.io/DNDReader/" \
  --add-topic pdf-reader,pdf,flutter,dart,android,windows,ubuntu,open-source
```

The `github-pages` environment only accepts deployments from `main`, which is why branches and pull requests
build and test but never deploy.

## Things worth knowing

- **The hero is an illustration**, labelled as one (`src/components/ReaderDemo.astro`). It is a self-contained
  block, so real screenshots can replace it without touching the rest of the hero.
- **Copy rules** are enforced by `tests/e2e/claims.spec.ts`: no superlatives or world-firsts, no unqualified
  private/secure/free/offline, no invented social proof, and every documented limitation present. Changing
  wording there is a deliberate act.
- **Windows and Android pages explain warnings; they never tell anyone how to get past one.** A test checks.
- **Budgets are commitments** (`tests/e2e/perf.spec.ts`): HTML 20 KB, CSS 20 KB, JS 10 KB (home) / 6 KB, fonts
  90 KB, LCP 1.5 s, CLS 0.02, TBT 50 ms, interaction 100 ms. A miss is a number to report, not a threshold to move.
- Fonts are Atkinson Hyperlegible Next and Mono (SIL OFL, licence shipped at `/OFL-Atkinson-Hyperlegible.txt`),
  self-hosted, Latin subset. They use `font-display: optional` with metric-matched fallbacks so the page never
  reflows when the font arrives.
- `scripts/make-og.mjs` regenerates `public/og.png`. It is committed, not built.
- The size of the Linux `.deb` (342 MB) is why release files stay on GitHub Releases: a repo rejects files over
  100 MB and a Pages site is capped at 1 GB. Serving them from your own storage later (for example Cloudflare R2)
  would change only the `url` field the release-data script produces.
