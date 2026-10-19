# DNDReader landing and download site: plan, as approved

> **Status: approved by the owner, then built.** This is the plan as it was presented, kept as the record of
> what was intended. The decisions the owner made, and the places the build departed from the plan, are listed
> first; where this document and the code disagree, the code and `site/README.md` are right.

## Owner's decisions (answers to section 13)

1. **Identity: the icon's navy and orange.** The app's own UI seed colour is teal `#2F5D62`
   (`lib/theme/colors.dart:6`), a different identity from the icon (`packaging/linux/deb/dndreader.svg`). The
   difference is deliberate and recorded here, not an oversight.
2. **Screenshots: ship the labelled illustration**, built as a swappable block (`ReaderDemo.astro`) so real
   screenshots can replace it later without a redesign.
3. **`/download/ubuntu/`** with a `/download/linux/` stub.
4. **"DNDReader"** everywhere; "DND" is expanded once, to explain the name.
5. **No runtime GitHub calls** from visitors' browsers.
6. **The owner enables Pages after the merge**, then About is updated; both gated on the live URL returning 200.

README limitation 15 (licence not chosen) was already fixed in #8 and is no longer an open item.

## Where the build departed from the plan

- **Hero lighting was added at the owner's request** (a faint ruled grid and two static glows, in the app's sky
  blue and the icon's orange). The plan said "no gradient soup"; this is two soft lights and a masked grid, with
  no motion, and the contrast of text over it is measured from real pixels in the test suite.
- **Fonts use `font-display: optional`, not `swap`**, with metric-matched fallbacks. A swap re-wrapped headings
  that sit near a line boundary on phones (CLS 0.03 against a 0.02 budget); `optional` removes reflow entirely.
  The trade-off: on a very slow first visit the text is set in the system fallback.
- **`/download/linux/` is a page of our own, not an Astro `redirects` entry.** Astro's redirect writes its
  destination and canonical without the base path, which would 404 on the project URL. Found by inspecting the
  build output; both bases are now tested.
- **The "started" panel and the hero illustration use paragraphs, not headings**, so the heading outline stays
  h1, h2, h3 (axe flagged the original).
- **Total Blocking Time is measured as Lighthouse defines it** (long tasks after First Contentful Paint). The
  first measurement counted every long task from navigation start and misread a one-off pre-paint layout task
  as 100 to 230 ms of blocking time; the 50 ms budget did not change. The pre-paint task is still reported.
- **Perf tests run alone, after the other tests**, because CPU contention from parallel workers distorted them.
- **The release event only dispatches the workflow on `main`**, because a `release` run executes at the tag's
  commit and Pages refuses deployments from tag refs.
- Android's apksigner fingerprint is shown in both forms (with colons as in the release notes, and without
  as `apksigner` prints it).

---

# The plan as presented

Written for: Ankit, the owner, deciding whether to approve the build.

## 0. Context

DNDReader has one published release (v0.3.0: Ubuntu, Windows, Android), an empty GitHub "About" box
(no description, no website, no topics), and no web presence. The goal is a static site on GitHub Pages
where a non-technical person goes from the home page to a working install without seeing a repository,
a release listing or an unexplained word. Clicking Download starts the file at once and the visitor stays
on our page.

You also asked: **when the site is live, update the repo's About and Website.** That is step 12 below,
gated on the live URL actually returning 200.

Nothing exists on disk yet: no branch, no `site/`. Plan mode blocks the branch and commit, so step 0 of the
build is `git checkout -b site/landing-page` and a first commit of this plan as `site/docs/PLAN.md`.

**Commit rules (from you, overriding the default attribution):** author is thisisankit27 only (git is
already `Ankit Srivastava <69184999+thisisankit27@users.noreply.github.com>`). No `Co-Authored-By`, no
"Generated with Claude Code" line in commits or any PR text. Branch, commit, push. **Do not merge.**

---

## 1. What I verified, what I only read, what I could not establish

**Verified by running it (today, 2026-10-19):**
- GitHub Releases API returns v0.3.0 with 5 assets. Names, sizes and SHA-256 **all match your table**. The
  API gives each asset a `digest` field (`sha256:...`), so checksums come straight from GitHub.
- All five asset URLs answer `200` with `content-disposition: attachment; filename=<exact name>` and the
  exact `content-length` (checked .deb, exe, arm64, v7a, x86_64). A `Range` request returns `206`, so
  resuming is possible server-side.
- The API replies with `access-control-allow-origin: *`. Unauthenticated limit is **60 requests/hour/IP**
  (the Actions token gets more).
- Pages is **not enabled** (`/pages` returns 404). Repo is public, Apache-2.0 is detected, About is empty,
  and you have `ADMIN`.
- `releases/latest` 302-redirects to the tag page (that is the one GitHub page a visitor could ever see,
  and only as the "download failed" fallback).
- **Tauri study with a real browser** (details in §3), light and dark, desktop and mobile, keyboard, computed
  styles, resource sizes.
- WCAG contrast ratios of my proposed palette, computed (§5).
- npm: astro 7.4.0, @fontsource atkinson-hyperlegible-next/-mono 5.3.0, @playwright/test 1.64.1,
  @axe-core/playwright 4.14.0 all exist.

**Environment finding:** the Playwright **MCP** browser cannot start here (Chrome aborts on a missing GNOME
GSettings schema). I ran the study with the Playwright library and its cached headless Chromium directly,
which still drives a real page (clicks, keys, computed styles, screenshots). Firefox/WebKit are not available
locally; CI will cover them.

**Read, not run (treat as documented, re-check at implementation):**
- GitHub docs: with a custom Actions workflow, a `CNAME` file is **ignored** (domain lives in Settings →
  Pages). Limits: published site 1 GB, soft 100 GB/month bandwidth, 10-minute deploy timeout.
- The `github-pages` environment only allows deploys from the default branch (so deploy runs on `main`
  only; PR/branch builds build and test but never deploy).
- Cloudflare R2: $0.015/GB-month, 10 GB free, Class B reads $0.36/M (10 M free), **no egress fees**.
- Windows signing: Azure Artifact Signing ≈ $9.99/month (limited regions; may need org history); SignPath
  Foundation is free for qualifying OSS but approval is uncertain and the publisher shown is "SignPath
  Foundation". Search results, not an account check.
- The README/docs for per-platform behaviour; the signing-key pin in `android-release.yml`.

**Could not establish:**
- How real browsers behave on a download click (does the page stay, which warnings appear). The Playwright
  suite tests Chromium/Firefox/WebKit; a real Windows machine and your Moto G60 should spot-check wording.
- Whether browsers actually resume a failed 342 MB download; whether Pages serves brotli (I budget in
  **gzip** to be safe).
- Whether Tauri's dark toggle persists (my probe grabbed the language select, not the theme button).
- Astro 7 specifics: not scaffolded yet. The plan uses only stable basics (static output, `site`/`base`,
  `getStaticPaths`, `redirects`).
- Windows-on-ARM behaviour of the x64 installer; the exact text of Android's ABI-mismatch error; any
  TalkBack/VoiceOver result (axe can't judge that, so a short TalkBack pass on your phone is a recommendation).
- Exact GitHub redirect behaviour when a custom domain is attached (documented, verify at the switch).

---

## 2. Product and UX analysis

**Positioning (no superlatives).** The product is a small, open-source, cross-platform PDF reader built
around one idea: looking something up does not cost you your place. DND = Do Not Disturb. No "first", "only",
"best" or "fastest" anywhere. Acrobat, Preview and Edge already offer web search on selected text, so the
claim is the *design intent and the constraint*, not novelty.

**Hero copy (draft):** "Look it up without losing your place." / "DNDReader is a small, open-source PDF
reader. Select a word, choose Find meaning, and search results open beside the page. Close them and you are
exactly where you were." Then "DND stands for Do Not Disturb" once, in plain words.

**Audience.** Primary: a non-technical reader who wants a PDF reader and will follow a button. Secondary:
a technical visitor who wants the hash, the licence and the limits. Design rule: the ordinary path never
requires the technical material; the technical material is one clear click away and never hidden.

**Name casing.** "DNDReader" everywhere (app, installer, repo); "DND Reader" only where explaining the pun.
(Your brief uses both. Tell me if you prefer otherwise.)

**What the site must carry** (all on the home page, not buried): AI Overview not guaranteed; no Google
sign-in in the panel; consent screens/CAPTCHA can appear; text-based PDFs only; the search panel needs a
network and loads Google; per-platform privacy as three separate statements; Android keeps a private copy;
Android ≈517 MB vs 300 MB target. No testimonials, counts, logos, awards, uptime. "One published release"
is stated plainly.

---

## 3. Reference study: v2.tauri.app (inspiration only; no markup, CSS, assets or copy reused)

Driven in a real browser at 1440×900 and 390×844, light and dark, plus keyboard.

**Works, and I will learn from it**
- **Tiny navigation:** four items (Guides, References, Blog, Releases), search, social icons, theme toggle.
  Nothing competes with the one primary action.
- **Skip link is the first Tab stop**, native focus rings everywhere; 35 KB JS and 18 KB CSS on the home
  page; system font stack so zero font cost; real `<title>`, description, canonical, OG image.
- **The install block as tabs** (Bash / PowerShell / Fish / npm…) with one command and a copy button. That
  is the right pattern for per-OS verify commands.
- **Docs layout:** left nav, 720 px reading column at 16/28 type, right "On this page" rail that collapses
  to a compact disclosure on mobile. Good reading measure; code block sits in the flow.
- **Dark mode** (studied properly): follows `prefers-color-scheme` (`data-theme="dark"` on `<html>`), with
  a sun/moon toggle. Not pure black and not blue-tinted: page `#1a1a1a`, raised surface `#262626`, hover
  `#383838`, body text `#d4d4d4` (11.7:1), headings white. The accent is **re-chosen, not inverted**: light
  uses blue `oklch(.5 .15 253)` (8.7:1), dark uses pale cyan `#a1edf7` (13.2:1), and the filled button turns
  pale cyan with dark text. The decorative grid and outline logo are dimmed rather than removed. Code
  blocks are a slightly raised surface with a hairline border. Both themes clear AA with margin.

**What I would do differently**
- The home page is a logo, a generic tagline and four identical cards with the **same rocket icon** on
  each; the hierarchy comes from cards, not from content. I will use whitespace and rules, and cards only
  for objects (the download card, a warning).
- Decoration (grid background, giant outline logo, sponsor avatar wall, 135 requests) does no work. Mine
  has one memorable element and nothing else.
- The OS tab strip is **clipped** ("Carg…") at desktop docs width and shows only four tabs on mobile with no
  scroll hint. I will use a segmented control that wraps, never clips.
- The copy button is an icon with a **hover-only** "Copied!" tooltip (`data-copied`). Mine shows a visible
  "Copied" label in the button and announces it through a live region.
- Dark mode is neutral grey; mine will be navy-tinted from the icon, with the accent re-picked per mode as
  they do, and a three-state toggle (System / Light / Dark) persisted, set before first paint.
- Tauri's page doesn't have to get someone to a download in one click; mine does.

---

## 4. Sitemap (one change from your list)

```
/                          home
/download/                 chooser (all platforms equal; suggestion on top if detected)
/download/ubuntu/          install page + download-started state
/download/windows/
/download/android/
/download/linux/           redirect stub -> /download/ubuntu/
/how-it-works/             the idea, the honest limits, privacy per platform
/404
```

**Why `ubuntu`, not `linux`:** the package targets Ubuntu 26.04. A `/linux/` URL tells people every distro
works. The stub keeps your original URL working. "Older versions" is a generated section on `/download/`,
shown only when a second release exists. Verification lives on each platform page (OS-specific commands),
not a separate page. Release notes link out to GitHub from the footer only.

---

## 5. Visual system

**Identity.** Derived from the icon (`packaging/linux/deb/dndreader.svg`): navy `#1f3a5f` page, orange lens.
*Note:* the app's own UI seed colour is teal `#2F5D62`, a different identity from the icon. I recommend the
icon (it is the brand mark on both desktop platforms). Say so if you'd rather follow the app UI. Wordmark =
the icon + "DNDReader" in the type, no custom logo.

**Type.** **Atkinson Hyperlegible Next** (body and headings; designed for legibility, fits the
colour-blind-safe stance) + **Atkinson Hyperlegible Mono** for commands. Self-hosted woff2, Latin subset.
Body 17/1.6, measure ≤ 62ch. Headings 700, tight tracking, fluid `clamp()`; h1 about 36→60 px. No
all-caps labels, no eyebrow above every heading, no accent-one-word headlines.

**Spacing.** 4 px base: 4 8 12 16 24 32 48 64 96 128. Section rhythm 96–128 desktop / 64 mobile. Page 1120
max, prose column 680.

**Colour (measured contrast, WCAG):**

| Token | Light | Dark | Measured |
|---|---|---|---|
| page | `#f6f8fb` | `#0e1726` | |
| surface | `#ecf0f6` | `#16233a` | |
| heading ink | `#14233a` | `#f1f4f9` | 14.8 / 16.3 |
| body | `#2b3a52` | `#d3dbe8` | 10.8 / 12.9 |
| muted | `#4d5b73` | `#9fb0c7` | 6.5 / 8.1 |
| link | `#1b5ea8` | `#8cc4f4` | 6.1 / 9.7 |
| orange as **text** | `#a8480a` | `#f09a58` | 5.5 / 8.1 |
| success / warning text | `#0b6b4d` / `#8a4b00` | `#5fd0a6` / `#f0b45a` | 6.1 / 6.4 · 9.5 / 9.7 |

- The icon's orange `#e8833a` is **2.55:1** on the page, so it is never used as text or a lone graphic.
- Hairline `#c8d1df` is 1.45:1: fine for decorative dividers, **not** for control borders. Anything that
  defines a button/input uses a ≥3:1 border (verified by test).
- In-app selection colours are the Okabe–Ito set from `lib/models/app_settings.dart`. The hero's
  selection is sky blue `#56B4E9` with fixed dark text in both themes (6.8 / 7.8:1), so meaning never
  rests on hue alone.

**Hero (the one memorable thing).** A real, tiny interaction instead of a screenshot: a paragraph on a
"page" with a phrase highlighted and a **Find meaning** pill. Activate it (click, Enter, or Ctrl+E as in
the app) and a panel slides in from the side (a bottom sheet on phones) while a small "you were here" marker
stays beside the paragraph; Esc closes it and focus returns to the pill. The panel shows **abstract
skeleton lines with an explicit "Illustration" caption**: no Google logo or UI imitation, no fake results.
One 200 ms user-triggered transition, none under `prefers-reduced-motion`. **Owner decision:** real
screenshots of the three platforms are better than any illustration; the repo has none (the Windows ones
were deliberately removed). If you supply them, they replace the illustration. Until then the demo is the
honest fallback.

**Motion:** nothing perpetual, no parallax, no scroll-triggered entrances. Hover is a colour change only.

**Components in play:** structure from ordered lists (a sequence, so numbers are earned) and rules. Not
everything is a rounded card. Objects only: download card, warning callout, checksum block.

---

## 6. The flow: download → install → verify

**Core mechanic (verified headers; browser behaviour to be tested):** every Download button is a plain
`<a href="https://github.com/…/releases/download/vX/<file>">`. GitHub answers with `attachment`, so the
browser downloads and **does not navigate**. No JS is needed for the download itself.

**The "download started" state is in-place, not a separate URL.** On click, JS lets the default action run
(download starts), then swaps the card into: "Download started: `<filename>` (`<size>`). Look in your
browser's downloads. Next: install ↓". It moves focus to that panel and announces it politely.
*Why not navigate to a thank-you page:* navigating away immediately can cancel the pending download request,
and auto-starting a 342 MB download on page load depends on browser policy and **re-downloads on refresh**.
The in-place design removes both problems. The platform pages are the destination: the home-page button
starts the file and reveals the same panel with "Continue to the install steps".

It never says "download complete" (the page cannot know). It says "started", and gives the direct link
again.

**Failure and edge states (each designed, each tested):**

| Situation | Behaviour |
|---|---|
| Arrive on an install page without downloading | Download card on top (idle), full steps below. Also correct for someone who has the file from another device. |
| Refresh after download | State is not persisted, so it returns to idle. No auto-download. Steps still visible. |
| Platform undetected / unsupported (macOS, iOS, ChromeOS, bot) | No suggestion, all three platforms equal. macOS/iOS: "DNDReader isn't available for X yet." No date, no promise. |
| Looks like Linux but not Ubuntu | "The Linux download is for Ubuntu 26.04. Other distributions aren't tested." Show a check command. |
| Wrong architecture | Android: arm64-v8a default, v7a/x86_64 explained ("only for older 32-bit phones", "emulators"). Ubuntu: `dpkg --print-architecture` must print `amd64`. Windows: x64 only; Windows-on-ARM untested, said plainly. Chromium `userAgentData` architecture is used when available and only to *warn*. |
| Browser blocks or warns | Describe each prompt in plain terms (multiple-downloads, "uncommon file", APK file-type warning). We explain, we do not coach anyone past a protection. |
| Download slow/failed | Shown size up front; direct link repeated; "check your browser's download list, most browsers can resume (the server supports it)"; last resort link to the release page. |
| **Checksum differs** | Red callout, plain words: **"Do not run or install this file. Delete it, download again, and if it still differs, open an issue."** |
| Old version URL / newer release exists | Page URLs are versionless, so they always offer the latest. A file you already hold from an older release is checked against the generated "older versions" hashes. |
| A platform asset missing from latest release | That page says "Not available in this release", the chooser disables it with the reason. It never silently links to an older file. |
| JavaScript off | Buttons still download, `<details>` still opens, copy buttons are absent (commands are selectable text). |

**Platform detection suggests, never decides.** "Looks like you're on Windows. Not right?" with the chooser
one click away. Local only, nothing sent anywhere. A pure function `detectPlatform(ua, uaData)` tested
against a table of real UA strings. Honest limits: browsers can't reliably give CPU arch on Linux, nor the
ABI on Android, so arm64 is the Android default and the rest are offered plainly.

---

## 7. Per-platform truth on each page

**Ubuntu.** `sudo apt install ./dndreader_<ver>-1_amd64.deb`, filename from data. "Built on and tested on
**Ubuntu 26.04**; dependencies come from that machine. Other releases and distributions aren't tested."
Size up front: **342 MB** (341,628,878 bytes, ≈326 MiB; browsers show 342 MB, so I use decimal MB and give
exact bytes in the checksum block). Reason in one sentence: Linux has no Flutter webview, so the build
bundles Chromium (CEF); about 1.5 GB installed. Verify: `sha256sum <file>`. No automatic updates (stated).

**Windows.** Windows 10 1809+ (x64). The installer is **unsigned**, so SmartScreen says "Unknown publisher".
Copy explains *why* (no code-signing certificate, no reputation yet), *what to verify* (the hash:
`Get-FileHash .\<file> -Algorithm SHA256`, or `certutil -hashfile <file> SHA256`), and that the decision is
theirs. **No step-by-step for clicking through the warning, ever.** Also: WebView2 Runtime needed (the
installer adds it if missing); per-user install, no admin.

**Android.** Android 8.0+ (minSdk 26). arm64-v8a is the default button. Describe the three things that will
appear: the browser's APK-type warning, Android's per-app "install unknown apps" permission (what it is,
that it's per app and can be switched off afterwards), and a possible Play Protect prompt. If Play Protect
blocks it: stop. Verification, optional and needing a computer: `sha256sum` and
`apksigner verify --print-certs <apk>`, with the fingerprint
`90:B1:F8:9D:69:CA:9F:26:14:0A:AC:C9:DC:B2:A8:A5:BF:49:43:97:F1:BF:E1:99:A1:26:02:7F:A7:17:D9:36`.
**Look for the digest, not the label**: build-tools 36 prints `Signer #1 certificate SHA-256 digest:`, 37
prints `V2 Signer: certificate SHA-256 digest:`. A checksum proves the file arrived intact; the signature
proves it came from this project. The page says which is which. Plus: private copy of each document (edits
to the original don't appear until reopened or shared again); memory ≈517 MB with a big document and panel
open vs a 300 MB target.

**Honesty about checksums (all platforms):** the hash and the file both come from the same project, so the
hash detects corruption and substitution *in transit*, not a compromised release. Said in one sentence.

---

## 8. Page wireframes

**Home** (single column, left-aligned, generous whitespace)
```
[icon DNDReader]            How it works   Download            [theme]
------------------------------------------------------------------------
H1  Look it up without losing your place.
p   One-paragraph description.  "DND = Do Not Disturb."
[ Download for Windows  ·  15.6 MB ]   Not Windows? Other downloads
small: Open source (Apache-2.0). Search needs an internet connection.
                                   |  page: …selected phrase… [Find meaning]
                                   |  (interactive illustration, panel slides in)
------------------------------------------------------------------------
How it works   1 Select  2 Find meaning  3 Close and carry on   (a true sequence)
------------------------------------------------------------------------
What it is, and what it doesn't promise   (two plain columns; AI overview,
                                           no sign-in, text PDFs, needs network)
------------------------------------------------------------------------
Download   three rows, not cards:  Ubuntu · Windows · Android
           each: one-line truth + size + [Download]
------------------------------------------------------------------------
What stays on your device   three separate statements (Linux / Windows / Android)
------------------------------------------------------------------------
Open source   Apache-2.0 · one published release (0.3.0) · source · issues
footer: licence · source · release notes · version & date (generated)
```

**Platform page**
```
H1  DNDReader for Ubuntu
[ Download card: Download · 0.3.0 · 342 MB · .deb ]   (idle → started panel in place)
   "Why 342 MB?"  (inline expand)        "Looks like you're on …  Not right?"
Before you start   requirements + one command to check
Install            ordered steps with copyable command
Check the download (optional)   <details>: hash, exact command for this OS, mismatch rule
What to expect     platform warnings (unsigned / unknown sources / sandbox profile)
If something goes wrong
Uninstall · Next: how to use it
```

**Chooser `/download/`:** detected suggestion (if any) on top, then Ubuntu / Windows / Android as equal rows
with requirement, size and file type; "Not sure which Android file?" disclosure; older versions (when any).

**How it works:** the idea, the 3 steps with keys (Ctrl+E, Esc), the full limits list, the per-platform
privacy table, "What leaves your device" (selected text goes to Google as a search; the PDF is never
uploaded), and the unresolved Google-terms question stated as the README states it.

---

## 9. Technical architecture

**Where:** `site/` in this repo, own workflow `site.yml`, `actions/deploy-pages`. Release data and the
signing pin are in this repo, so no cross-repo token; it matches the project's isolated-directory habit.

**Framework: Astro** (7.4.0 on npm today, pinned by lockfile). Static HTML, zero JS by default, typed data
and layouts at build time, built-in redirects and `getStaticPaths`. Scripts are small vanilla files (copy,
detect + started state, theme, hero demo). No React/Vue. Rejected: Eleventy (fine, but less structure for
typed data and the component set), Next export (JS and weight for nothing), Hugo (no TypeScript for the data
model), hand-written HTML (would copy data into pages). Cost: a Node toolchain to keep updated.

**Styling:** hand-written CSS, custom properties as tokens, `@layer reset, tokens, base, components`, scoped
component styles. No Tailwind: a ~15-token system doesn't need it and utility markup makes contrast review
harder.

### Release data: generated, never typed

One model, built from the API at build time:
```
Release { version, tag, publishedAt, notesUrl }
Asset   { id, platform: ubuntu|windows|android, arch, format, filename, url,
          bytes, sha256, contentType }
```
- `scripts/fetch-releases.mjs` calls `GET /repos/thisisankit27/DNDReader/releases`, drops drafts and
  pre-releases, picks the highest semver as latest, maps assets with **one rules table** (filename regex →
  platform/arch/format), writes `src/data/releases.generated.json` (git-ignored) with
  `status: ok | unavailable | no-releases` and `source`.
- Editorial content (requirements, steps, warnings) is version-independent and lives in
  `src/content/`, with `{filename}`/`{version}` placeholders filled from data, so commands can't drift.
- **Checksum:** the API `digest`; if absent, the `sha256  filename` block in the release body; **if both
  exist and disagree the build fails**; if neither, the page says "published checksum unavailable" and shows
  none. Nothing is invented. The 342 MB .deb is never downloaded in CI.
- **URL guard:** every asset URL must match `https://github.com/thisisankit27/DNDReader/releases/download/<tag>/<name>`
  or the build fails.
- **Signing fingerprint** is a property of the key, not a release, so it is pinned once in
  `site/src/data/signing-key.json`. A CI check asserts it equals `EXPECTED_CERT_SHA256` in
  `android-release.yml` (read-only; that file is not touched) and equals the fingerprint in the release
  notes when present. A key change becomes a loud, reviewed event.

**Regenerate on every Pages build, not committed and refreshed by a scheduled job.** Reasons: a committed
JSON can drift and needs a bot to push to `main` (protected, and you merge by hand); regeneration makes drift
impossible by construction. Build triggers: push to `main` touching `site/**`; **`release` published /
edited / deleted** (staleness window is minutes); `workflow_dispatch`; a weekly cron as a safety net. Note: a
release created by `GITHUB_TOKEN` wouldn't fire `release`; yours are manual, so they do.

**API failure policy (the site must still build and degrade honestly):**

| Case | Result |
|---|---|
| 403 rate limit / 5xx / network | 3 retries with backoff, honouring `retry-after`. Then `status: unavailable`. |
| `unavailable` in CI | Site **builds** (so checks pass) in degraded form: no version, size or hash anywhere; download buttons become one link to the release page with "Download links are temporarily unavailable." **The deploy job is skipped**, so the last good site stays live rather than being replaced by a degraded one. |
| `unavailable` locally | Use `.cache/` last-good file marked `source: cache` (dev banner only, never shown to visitors), else degraded. |
| No releases | "No release is published yet." |
| Malformed data (non-integer size, bad digest, URL off GitHub, digest/body mismatch) | **Build fails.** That's a bug or an integrity event, not an outage. |

**No runtime calls to GitHub** from visitors' browsers. A "newer version available" banner would send every
visitor's IP to api.github.com; for a project whose pitch is "no telemetry" I'd rather accept a minutes-long
staleness window. (CORS is open and limits are 60/h/IP if you ever want it. Your call.)

### Base path and the custom-domain switch

- `site/astro.config.mjs` reads `SITE_URL` and `SITE_BASE` (defaults `https://thisisankit27.github.io` and
  `/DNDReader`). Every link and asset goes through one `url()` helper; no literal `/` paths in components.
  Canonical, OG and sitemap URLs derive from the same two values.
- A test builds under **both** configs and crawls every internal `href`/`src` and every redirect, failing on
  a 404 or a root-absolute leak. This is the real guard against the classic Pages failure.
- **Switch runbook** (also in `site/README.md`): (1) at your DNS provider, add the GitHub Pages records first
  (harmless on their own); (2) set repo variables `SITE_URL=https://<domain>`, `SITE_BASE=/` and re-run the
  workflow; (3) immediately add the domain in Settings → Pages; (4) wait for DNS check and certificate;
  (5) tick **Enforce HTTPS**; (6) update the repo Website field. No `CNAME` file is needed with Actions
  publishing (docs, re-check; I'd add `site/public/CNAME` only once a domain exists). GitHub documents that
  `github.io/DNDReader/…` then redirects to the same path on the new domain, so shared links keep working
  (verify at the switch). There is a window of a few minutes between steps 2 and 3 in which the old URL's
  assets use the new base; on a site with no visitors that is acceptable, and doing 2 and 3 back to back
  minimises it. Relative URLs would remove it but Astro doesn't support them first-class, so I'm not
  fighting the framework.

### Workflow `site.yml` (new; no other workflow touched)
Triggers above plus `pull_request` on `site/**`. Least-privilege permissions; concurrency group `pages`.
**build:** checkout, Node 22 with npm cache, `npm ci`, fetch releases with `GITHUB_TOKEN`, check pin, build,
unit tests, Playwright suite against `astro preview` (both bases), upload Pages artifact. **deploy:** only on
`refs/heads/main`, only if data status is `ok`, environment `github-pages`. Action versions to be pinned to
the same style as your existing workflows and confirmed when written. A guard step on `site/*` branches
fails if `git diff --name-only origin/main...HEAD` lists anything outside `site/` and `site.yml`.

### Performance budget (gzip; I could not confirm Pages serves brotli)
| Metric | Target |
|---|---|
| HTML per page | ≤ 20 KB |
| CSS total | ≤ 20 KB (one file) |
| JS | home ≤ 10 KB, platform pages ≤ 6 KB, no framework runtime |
| Fonts | ≤ 90 KB total (3 woff2: sans regular, sans bold, mono); `font-display: swap`, size-adjusted fallbacks, preload the body file only |
| Images | none on the page except inline SVG |
| LCP | ≤ 1.5 s on simulated Slow 4G (limit 2.5 s) |
| CLS | ≤ 0.02 (the detect-upgraded button reserves its size) |
| INP | ≤ 100 ms; TBT ~0 |
Asserted by a Playwright test reading transfer sizes and by Lighthouse in CI as a report.

### SEO
Unique title and description per page; canonical from `SITE_URL+BASE`; Open Graph/Twitter card with one
committed `og.png`; `SoftwareApplication` JSON-LD (name, OS, licence, version) with **no ratings or counts**;
sitemap + robots; `lang="en"`; 404 is `noindex`. Titles say what it is ("Download DNDReader for Android,
version 0.3.0"), not keywords.

### Components (only where reuse is real)
`Layout` (head/SEO) · `SiteHeader` (+`ThemeToggle`) · `SiteFooter` · `PlatformList` (home and `/download/`) ·
`DownloadButton` · `DownloadCard` (button + started panel + live region + fallback; 3 platform pages) ·
`CodeBlock` (copy) · `ChecksumBlock` (hash, per-OS commands, mismatch callout) · `Callout` (warning/note) ·
`Steps` · `Disclosure` · `PrivacyTable` (home and how-it-works). Page-only, not components: hero and reader
demo.

**Accessibility, designed in:** semantic landmarks, one `h1` per page and no skipped levels, skip link first,
2 px offset focus ring ≥3:1, 44 px targets (24 px hard minimum), 320 px reflow with no horizontal scroll,
`prefers-reduced-motion`, `forced-colors` not broken. Copy: the button label changes to "Copied" (visible)
and a single persistent `role="status"` region announces "Copied: <what>", with a select-and-Ctrl+C fallback
if the clipboard API is refused. **Long commands wrap on phones** (`pre-wrap`, `overflow-wrap:anywhere`,
copy button on its own row) instead of scrolling sideways; hashes break at a fixed point and copy from a data
attribute so grouping never corrupts what's copied.

---

## 10. Implementation order (each step verified before the next; small commits)

0. Branch `site/landing-page`; commit this plan as `site/docs/PLAN.md`.
1. Scaffold Astro in `site/`, config, `url()` helper, `.gitignore`, empty `site.yml` (build only).
2. Release-data script, rules table, fixtures, unit tests, failure matrix.
3. Tokens, fonts, layout, header/footer, theme toggle (no flash).
4. `CodeBlock`, `Callout`, `Steps`, `Disclosure`.
5. Platform pages + `DownloadCard`, detection, started state.
6. Chooser, then home (hero demo last, since it's the riskiest).
7. How-it-works. 8. SEO, OG, sitemap, 404, redirect stub.
9. Playwright + axe suite, budgets, claims guard.
10. `site.yml` deploy job and the `site/` diff guard.
11. Visual review loop: screenshots light/dark × desktop/mobile against §3 notes; fix; critique.
12. Final: `git diff main --stat` shows only `site/**` and `.github/workflows/site.yml`; push the branch; stop.

**After you merge (your step):** I'd then, with your OK, run
`gh api -X POST repos/thisisankit27/DNDReader/pages -f build_type=workflow` to enable Pages (I have `ADMIN`)
and trigger the workflow. When `https://thisisankit27.github.io/DNDReader/` returns 200 and its download
links pass the Playwright link check against the live site, then update About:
```
gh repo edit thisisankit27/DNDReader \
  --description "A small, open-source PDF reader: select text, choose Find meaning, and search results open beside the page. Close them and you are back where you were. Ubuntu, Windows, Android." \
  --homepage "https://thisisankit27.github.io/DNDReader/" \
  --add-topic pdf-reader,pdf,flutter,dart,android,windows,ubuntu,open-source
```
(No superlatives; wording is yours to edit.) The homepage is updated again at the custom-domain switch.

---

## 11. Playwright test plan (`@playwright/test` 1.64.1, Chromium + Firefox + WebKit in CI; Chromium locally)

1. **Navigation:** every header/footer link lands where it says; skip link first; 404 page; `/download/linux/`
   redirects.
2. **Download links resolve to real assets:** for every generated asset, a request follows redirects and
   asserts `200`, `content-disposition: attachment` with the exact filename, and `content-length == bytes`.
   Plus **one real download** (the 15.6 MB .exe) asserting the `download` event, suggested filename, and that
   the SHA-256 of the received file equals the hash on the page. The .deb gets a ranged request only. Tagged
   `@network`; also runs as a post-deploy smoke against the live URL.
3. **Platform selection:** a table of real UA strings (Android Chrome/Samsung/Firefox, Windows
   Chrome/Edge/Firefox, Ubuntu Firefox/Chrome, ARM Linux, macOS, iPhone, iPad-as-Mac, ChromeOS, bot) → CTA
   label and href; "Not right?" opens the chooser; unknown shows no suggestion; `userAgentData` mocked for
   the arch warning.
4. **Download-started state:** click → `download` event fires, URL unchanged, panel visible, focus moved,
   live region text correct; **refresh → idle and no download event**; Escape/keyboard paths.
5. **Copy buttons:** clipboard permission granted → clipboard equals the expected command/hash (with
   filename from data), visible "Copied" state, live region announced; denied-permission fallback; JS-off
   context has working links and `<details>` and no dead copy buttons.
6. **Responsive:** 320, 390, 768, 1024, 1440 — no horizontal overflow, code wraps, targets ≥ 24 px (44 px
   reported), screenshots archived for review. Visual baselines are added only after the design settles.
7. **Accessibility:** axe on every page × light/dark × desktop/mobile (zero serious/critical); heading
   order; visible focus on every control; keyboard-only run through each flow; reduced-motion removes the
   transition; forced-colors screenshot; a test recomputes the token contrast table from the built CSS.
8. **Error states via fixtures:** `ok`, `unavailable`, `no-releases`, missing Windows asset, extra unknown
   asset (ignored), pre-release only, two releases (older-versions list), digest/body mismatch (**build
   fails**), URL off GitHub (**build fails**). Rendered text asserted for each, including the checksum-mismatch
   callout wording.
9. **Base path:** build and preview under `/DNDReader/` **and** `/`; crawl every internal URL; no
   root-absolute leaks; canonical/OG/sitemap match the config.
10. **Claims guard** (text test over built HTML). Forbidden: "first", "only reader", "world", "best",
    "fastest", "AI-powered", unqualified "private/secure/offline/free". Required: AI Overview not
    guaranteed; no Google sign-in; text-only PDFs; three separate privacy statements; network needed;
    Android private copy; ≈517 MB vs 300 MB.
11. **SEO:** unique title/description per page, canonical, OG tags, valid JSON-LD, sitemap completeness.
12. **Performance budget** from §9, and theme: toggle persists and sets `data-theme` before first paint.

---

## 12. Things I noticed that you should know (outside `site/`, so I will not touch them)

- `README.md` limitation 15 still says **"The licence … has not been chosen yet (no LICENSE file)"**. That
  became false with #7 (Apache-2.0). The site links the licence; the README contradicts it until you fix it.
- Size wording differs: README "~330 MB", release notes "~326 MB" (that's MiB), actual 341,628,878 bytes =
  **342 MB** in the units browsers display. The site derives size from bytes.
- GitHub About is empty (description, website, topics): covered by step 12.

## 13. Decisions for you (defaults chosen; say if any should change)

1. **Identity:** icon navy/orange (recommended) vs the app's teal.
2. **Screenshots:** supply real ones (best) vs the labelled illustration (default).
3. **`/download/ubuntu/`** with a `/download/linux/` stub (recommended) vs `/download/linux/` only.
4. **"DNDReader"** as the product name everywhere.
5. **No runtime GitHub calls** (recommended) vs a live "newer version" banner.
6. **Pages enablement** by me after you merge (recommended) vs you in Settings.

## 14. Honest notes you asked for

**Big files cannot live on Pages.** A repo rejects files over 100 MB and a Pages site is capped at 1 GB, so
the 341,628,878-byte .deb cannot be committed or served from Pages in any arrangement. GitHub Releases
stays the file host and is fine: the page stays ours, the file arrives as an attachment, and the only GitHub
URL a visitor sees is in their download bar.

**Hosting the bytes ourselves later** would mean object storage + CDN behind your domain, e.g. **Cloudflare
R2** (public bucket on a subdomain). Approximate cost from Cloudflare's published prices: ~0.4 GB of release
files ≈ $0 within the 10 GB free tier; reads are 10 M/month free then $0.36/M; **egress is free**. Costs are
mainly your time: a domain you control, a Cloudflare account, an upload step in the release process,
and keeping hashes in sync (the same generator can read from R2 instead). It also moves you from GitHub's
bandwidth to your own. Nothing in this plan depends on it, and the data model keeps `url` as a field so a
later move is a one-file change.

**Windows signing is the real fix for SmartScreen.** Options: Azure Artifact Signing ≈ $9.99/month (regional
and eligibility limits), SignPath Foundation (free for qualifying OSS, approval uncertain, shows their name),
or a purchased certificate (annual cost). Signing helps but reputation still builds with downloads. Until
then the site says plainly that it's unsigned and why; it never tells anyone to click through.
