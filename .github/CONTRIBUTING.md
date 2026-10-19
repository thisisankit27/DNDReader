# Contributing to DNDReader

Thanks for looking. DNDReader is a small, solo, open-source PDF reader (Apache-2.0) built around one idea: looking something up should not cost you your place. Small, careful contributions are welcome.

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go through the private form in [SECURITY.md](SECURITY.md), never a public issue.

## Before you start

- **Bugs and download problems:** open an issue using the template. Say the platform, the version (Menu, then About) and what you saw.
- **Features:** open an issue first. A few things are deliberately out of scope (see "Not included" in the [README](../README.md)): OCR, DOCX/EPUB, annotation or editing, cloud storage, accounts, sync, a general-purpose browser, AI of any kind.
- **Known limitations are not bugs.** An AI Overview not appearing, no Google sign-in in the panel, consent screens, and text-based PDFs only are all documented in the README and on [the website](https://dnd-reader.vibethroughcode.com/how-it-works/).

## Where things live

| Path | What |
|---|---|
| `lib/` | the Flutter application (shared by every platform) |
| `linux/`, `windows/`, `android/` | per-platform runners and native code |
| `packaging/` | the Ubuntu `.deb` and Windows installer |
| `docs/` | plans, the progress log, release and owner-test notes |
| `site/` | the website (Astro); see [`site/README.md`](../site/README.md) |
| `test/`, `integration_test/` | unit/widget tests and the per-engine conformance suite |

## Building and checking the app

Flutter 3.47.7 or newer and the prerequisites for your platform are in the [README](../README.md). Before opening a pull request:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

CI runs these and the per-platform builds. Two things it will reject: a committed `pubspec_overrides.yaml` (a local-development file), and a change that is not formatted.

## Changing one platform

A change for one platform should not mean re-testing every platform. The search panel is behind the `SearchWebView` adapter contract ([`docs/search-web-view-contract.md`](../docs/search-web-view-contract.md)), with a conformance suite and per-platform CI, so keep platform code behind that contract and say which platform your change affects.

## Saying what you verified

This project writes down what was actually observed, and what was not. In your pull request, separate **verified** (you ran it, and how) from **not verified** (you only read it, or could not test it). Please do not claim a platform works unless you ran it there.

- [`docs/progress.md`](../docs/progress.md) is an append-only log of observations.
- The repository is public: **do not commit screenshots, machine names, user names or personal paths.** Describe what you saw in text.
- Never commit a signing key or keystore. Release signing is described in [`docs/android-release.md`](../docs/android-release.md).

## Working on the website

```bash
cd site
npm ci
npm test        # unit tests, then Playwright and axe on every page
```

Release details (version, size, checksum) are generated from the GitHub Releases API at build time and never typed into a page. Copy rules are enforced by tests: no superlatives or world-firsts, no unqualified claims about privacy, security or being free or offline, and every documented limitation stays visible. Performance and accessibility budgets are commitments; if a change misses one, report the number rather than loosening the budget.

## Pull requests

- Keep them small and focused, with a short imperative title (for example, "Fix the page field losing focus").
- Branch from `main`; use a descriptive branch name.
- The template asks what changed, why, and what you verified.
- Contributions are accepted under the project's Apache-2.0 licence (section 5 of the licence). There is no separate CLA.
