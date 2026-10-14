# DNDReader Windows verification — results

> **Screenshot IDs.** This log was written during the run and cites the original capture names. Only a curated,
> cropped subset is committed (full-desktop captures stay on the verifying machine). Mapping to
> `screenshots/`: `01-install-launch`->`01-installer-wizard`, `03-launch-empty`->`02-launch-empty-state`,
> `05c`->`03-select-multiline`, `05d`->`04-select-near-bottom-pill-under-taskbar`, `06a`->`05-find-meaning-google-loaded`,
> `07c`->`06-result-click-spurious-error`, `07d`->`07-cloudflare-check-page`, `07h-back-3`->`08-back-disabled-while-page-shown`,
> `08d`->`09-ctrl-t-contents-after-panel-close`, `09c`->`10-typing-in-panel-works`, `12b`->`11-page-field-focus-outline-after-enter`,
> `13-fs-in-1`->`12-fullscreen`, `14f`->`13-fullscreen-with-panel`, `15b`->`14-about`, `16d`->`15-light-theme`,
> `21a`->`16-open-with-list`, `22a`->`17-offline-simulated`, `24a`->`18-right-click-menu`.
> The hand-off summary for another Claude session is [REPORT.md](REPORT.md).


Branch `feat/windows-port` @ `a4dfa20`. Installer from CI run `38519350754` (sha256 `6df97f31661c29e1de8502a222b729b8355515bd25f646f16170db29e31e4fe3`, **unsigned**).
Machine: Windows 10 22H2 (19045), 1920x1080 at **150% scale**, WebView2 Runtime **155.0.4283.45**.
Method: ordinary synthetic mouse/keyboard input + full-screen captures. No code changed. Only `test_fixtures/*.pdf` opened.
Labels: **verified** (observed), **read** (source/doc), **not verified**.

## Verdict

**Not ready to merge.** The app installs, renders, and the search panel works well — but it **crashes every time it is quit after a search has been used**, and as a consequence the "search data is deleted when you quit" promise is false in practice.

## Defects (ranked)

| # | Severity | Finding | Evidence |
|---|---|---|---|
| D1 | **High** | Quitting after any Find meaning use: ~5.4 s hang, then crash (`0xc0000005` in `flutter_windows.dll+0x1551f`, then `0xc000041d`). The temp profile (`History`, `Web Data`, `Login Data`, caches, ~600 files / 68 MB) is **left behind**. Quitting without ever searching: 338 ms, no crash, nothing left. | 3/3 reproduced (graceful close, real X-click, panel closed first with Esc). Windows Application Error + WER events, same fault offset each time; PIDs match. Screenshots n/a (it is a crash); event log excerpts in this file's appendix. |
| D2 | Medium | Stale profile is swept on the **first search of the next session**, not at launch (About/README say "next launch"). With D1, browsing data sits in `%TEMP%` until the user searches again. | verified: folder still present 10 s after relaunch; removed on first Find meaning. |
| D3 | Medium | Clicking a result that goes through a Cloudflare interstitial (thesaurus.com) shows **"Couldn't load results"** over a page that is actually loading, flaps between error and page, and leaves **Back disabled while a page is shown**. No real network failure. | `07c`, `07d`, `07e`, `07f`, `07g`, `07h-back-3` |
| D4 | Medium | After typing a page number + Enter, document shortcuts (`Ctrl+R`, `Ctrl+Shift+R`) do nothing until the document is clicked; the field still shows its focus outline. Source says `_submit` unfocuses. Parity with Linux unknown. | `12b/12c/12d`; pixel diff 0.0 for both shortcuts; works after a document click (`11c`,`11d`). |
| D5 | Medium | At 150% scale on 1080p the **default first-run window is taller than the work area** (rect `15,15 1650x1106`; work area bottom 1034). Bottom ~87 px hidden under the taskbar; the selection pill near the bottom edge is hidden. Looks like the size clamp is applied before DPI scaling. | `03`, `05d`; first run (no `window-size` file existed) |
| D6 | Low | Default Flutter icon in title bar / taskbar / Open With; Open With shows `dndreader` (lowercase). Uninstall entry has empty Publisher. | `03`, `21a` |
| D7 | Low | Uninstall leaves `HKCU\Software\Classes\Applications\dndreader.exe` (`shell\open`, `SupportedTypes\.pdf`), `%APPDATA%\dndreader\window-size`, `%APPDATA%\com.dndreader\dndreader\shared_preferences.json`. | registry/file listing after uninstall |

## Checklist (report §7)

| # | Step | Result |
|---|---|---|
| 1 | Install | **Pass** (verified: 21 files, ProgId, OpenWithProgids, Start-menu, Uninstall key; per-user, no UAC; no libcef). Wizard opened straight at the destination page. **SmartScreen: not observed** — I ran it with a synthetic Mark-of-the-Web and none appeared; the owner's own install is the real test. Installer is `NotSigned`. |
| 2 | WebView2 detection | Runtime present → Runtime install skipped is **consistent** (verified registry). Bootstrapper path **not performed** (would need removing the Runtime). |
| 3 | Launch | **Pass** — title `DNDReader`, empty state, process responsive (`03`). |
| 4 | Ctrl+O, Open with | **Pass**: Ctrl+O dialog + fixture opened (`04c`,`04d`). "Open with" lists `dndreader` (`21a`); launching `dndreader.exe "<pdf>"` (registered command) opens it (`21c`); default `.pdf` handler stayed `ChromeHTML`. The `rundll32` OpenAs route passed a path with a trailing space and the app showed the previous document — **not conclusive**; real Explorer right-click not performed. |
| 5 | Select word / phrase / multi-line / edges | **Pass**, pill under selection (`05a`–`05c`). Near bottom: see D5 (`05d`). |
| 6 | Find meaning (pill, Ctrl+E, right-click) | **Pass** (`06a`, `24a`): panel ≈433 logical px, Google results load, **no CAPTCHA, no consent wall**. |
| 7 | In panel: wheel, click result, Back, Open in browser | wheel **pass**; Open in browser **pass** (Edge, `22b`); click result / Back **fail** — D3. |
| 8 | Esc closes panel, shortcuts immediately, click panel → Esc | **Pass** (`08a`–`08d`, `09`). |
| 9 | Shortcuts | `Ctrl+O/E/T/R/Shift+R`, `F11`, `Esc`, header icon: **pass** except D4. Icon toggles both ways. |
| 10 | Page field, rotate, themes, recents, selection colour | **Pass**; Light theme (`16d`), recents lists `prose.pdf` (`16f`), 5 selection colours (`24b`). Dark/Follow-system confirmed; selection-colour *application* not checked. Page field: D4. |
| 11 | Wheel / zoom | **Measured** below. `Ctrl`+wheel zoom **pass** (`10a`/`10b`; restores pixel-identically). |
| 12 | Persistence | **Pass**: window size (1200x799 vs 1200x800 set), zoom, page 2 and document restored (`17b`, `19b`). Window position not restored (size only). |
| 13 | Privacy | **Fail** — D1. |
| 14 | About | **Pass** (`15b`): version, "Microsoft Edge WebView2 Runtime 155.0.4283.45", temp-folder line, no CEF. |
| 15 | Win11 yellow border | **Not performed — cannot be ruled out from Windows 10 (build 19045).** |
| 16 | Offline/failure | **Pass via simulation** (dead local proxy, `22a`): "Couldn't load results", Retry, Open in browser. Not a real disconnect (would have cut the session). |
| 17 | Uninstall | **Pass with leftovers** — D7. Install dir, ProgId, OpenWithProgids, Start-menu, Uninstall key removed. |

## The three flagged risks

1. **Focus — mostly fine.** Typing into the panel's search box works after a click (`09c`); clicking the document closes the panel (by design) and arrow keys then scroll the document (`09e`); `Esc` after clicking in the panel closes it (`08a`); `Ctrl+T`/arrows work immediately after the panel closes (`08c`,`08d`). No bouncing observed. The one focus defect is D4 (page field).
2. **Wheel constant — measured.** `WheelScrollLines = 3`. One notch = **171 physical px = 114 logical px at 150% scale**, identical in 6/6 single-notch samples. Target was ≈100: it is ~14% over. A 5-notch burst could not be measured reliably (shift exceeded my match window). Not measured at 100% scale. Panel (Chromium) scrolled ≈125 physical px/notch.
3. **Full screen — passes.** `F11`↔`Esc` ×4, `F11` toggle, header icon in/out ×2, icon-in/`Esc`-out, `F11`-in/icon-out: **10/10**; every restore returned exactly to `15,15 1650x1106`. Full screen covers the taskbar (`0,0 1920x1080`); the panel renders in full screen (`14f`). `Esc` order matches source: leaves full screen first, panel next.

## Other confirmations

- **WebView2 Runtime**: `HKLM\SOFTWARE\WOW6432Node\…\{F3017226-…}\pv` = `155.0.4283.45`; native HKLM and HKCU keys absent.
- **Process tree** (panel open): `dndreader.exe` → `msedgewebview2.exe` (browser) → 7–9 children (gpu ×1, utility ×4, renderer ×3, crashpad). Command line has `--user-data-dir=%TEMP%\dndreader-search-<pid>\EBWebView` and **no `--no-sandbox`** on any child. Sandbox integrity level itself **not verified**.
- **Privacy folder**: created when the panel opens (`dndreader-search-<pid>`, with `.dndreader-lock`). Clean quit: **not removed** (D1). Abrupt kill: not removed, no orphaned WebView2 processes (expected). Next session's first search: **swept** (both cases verified).
- **File association**: ProgId `DNDReader.pdf` + `OpenWithProgids` + `Applications\dndreader.exe` registered per-user; default handler not seized.
- **Uninstall** leftovers: see D7; uninstall took 2 s, exit code 0.

## Not verified

Windows 11 capture border; SmartScreen as the owner saw it; Runtime-missing bootstrapper path; per-machine install; EEA/UK consent wall; 100% display scaling; real network disconnect; real Explorer right-click Open With; whether `onExitRequested` runs (D1 root cause not established — candidates: teardown ordering of controller disposal vs texture/WGC at exit; engine shutdown fault).

## Harness notes (for honesty)

- First `Ctrl+O` failed only because my input helper sent scan code 0; fixed, then worked. Not an app defect.
- One stray click landed on the VS Code window before I fixed a helper-name collision (`Move` alias); VS Code then showed an `Untitled-1` tab — possibly created by that click. Please close it if it's unwanted.
- Screenshots `24a`/`24b` were cropped to the app region because Edge (with an email address) was behind them.

## Appendix — crash events (Windows Application log)

```
06:42:44  Application Error  dndreader.exe 0.1.5.1  flutter_windows.dll  0xc0000005  offset 0x1551f  pid 0xfe0 (4064)
06:42:47  Application Error  ...                                          0xc000041d  offset 0x1551f  pid 0xfe0
06:44:02  Application Error  ...                                          0xc0000005  offset 0x1551f  pid 0x17cc (6092)
06:44:05  Application Error  ...                                          0xc000041d  offset 0x1551f  pid 0x17cc
06:45:49  Application Error  ...                                          0xc0000005  (panel closed with Esc first, exit took 5.4 s)
06:45:51  Application Error  ...                                          0xc000041d
```

Not crashing: quit with no search used (338 ms, 0 events).

## Files

`verification\*.png` screenshots (numbered per step); `verification\installer\` = downloaded artifact (15 MB, **do not commit**). Everything under `verification\` is untracked.
