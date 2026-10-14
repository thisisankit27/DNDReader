# DNDReader Windows port — verification report and hand-off

Written for: **another Claude Code session** (and the owner) picking this up cold — to fix the defects below on
the Windows port, or to review how the claims were evidenced. It assumes no memory of earlier sessions.

- **Subject:** branch `feat/windows-port` @ `a4dfa20`, installer `DNDReader-0.1.5-setup-x64.exe` from GitHub
  Actions run `38519350754` (sha256 `6df97f31661c29e1de8502a222b729b8355515bd25f646f16170db29e31e4fe3`, unsigned).
- **Machine:** Windows 10 22H2 (19045), 1920×1080 at **150 %** scale, WebView2 Runtime **155.0.4283.45**.
- **Method:** the installed app driven with ordinary synthetic mouse/keyboard input, observed through screenshots,
  process/registry/event-log inspection. **No source was changed.** Only `test_fixtures/*.pdf` were opened.
- **Labels:** **verified** = observed on a running app; **read** = from source/docs; **not verified**.
- Detail log with every step: [RESULTS.md](RESULTS.md). Screenshots: [screenshots/](screenshots/) (curated, cropped).
  Input/screenshot helper used: [tools/input-helpers.ps1](tools/input-helpers.ps1).

## 0. Status after the Windows fix session (read this first)

All seven defects were addressed on `feat/windows-port` (one branch per fix, `--no-ff` merges; **170 tests**,
`dart format`/`flutter analyze` clean). Evidence below is from a **local** debug *and* release build on the
same Windows 10 / 150 % machine. **CI on the final head is still to be confirmed** (see the owner's checklist).

| # | Defect | Status | How it was verified |
|---|---|---|---|
| D1 | Crash on quit after a search; profile left behind | **Fixed** | The runner now defers `WM_CLOSE`, asks Dart to run shutdown hooks over `dndreader/lifecycle`, then closes. Real X-click, `Esc`→X and `CloseMainWindow`: **0 Application Error events, nothing left in `%TEMP%`**, ~0.5–0.8 s (debug and release). |
| D2 | Sweep at first search, not launch | **Fixed** (Ubuntu session), **re-verified on Windows** | `REVERIFY-574c0e9.md`. |
| D3 | Spurious "Couldn't load results"; Back desync | **Fixed** | Gated click (dictionary.cambridge.org, thesaurus.com) shows the interstitial then the page, no failure overlay; Back returns to the results. Real `WebErrorStatus` logged: `unknown` (0) for the aborted challenge navigation. |
| D4 | Shortcuts dead after page-field Enter | **Fixed** (Ubuntu session), **re-verified on Windows** | `REVERIFY-574c0e9.md`; the "focus outline persists" note was a mouse-hover misread (corrected there). |
| D5 | First-run window taller than work area at 150 % | **Fixed** | Real first run: `15,15 1650×1004`, bottom at 1019 inside a 1034 px work area (was 1650×1106). `FitToWorkArea` has a 184-check MSVC test, also run in CI. 100/125/200 % are verified by that test only. |
| D6 | Default icon, "dndreader", no publisher | **Fixed** | Brand icon in title bar, taskbar and Open With; `FileDescription`/`ProductName` = DNDReader; Publisher `thisisankit27` in the uninstall entry. |
| D7 | Uninstall leftovers | **Fixed** | Uninstall removed the `Applications\dndreader.exe` key, `%APPDATA%\dndreader`, `%APPDATA%\com.dndreader` and a seeded stale `%TEMP%\dndreader-search-*`; default `.pdf` handler untouched. **Decision:** settings are removed on uninstall (they hold recent-file paths); an upgrade keeps them. |

**Residual / not done**

- **Quit with a live Google page is not always sub-second.** Of 11 live release quits, 8 took 0.55–0.75 s and
  3 took 2.5 s, 3.4 s and 8.0 s; a leftover folder was seen after the slow ones and was removed by the next
  launch's sweep. With no network (dead proxy) 6/6 took 0.65–0.69 s. In the one timed live debug run the only
  slow step was the profile delete (~400 ms), which retries up to 10 × 300 ms while WebView2's browser process
  finishes exiting. So: bounded and recovered by D2, **not eliminated**, and not root-caused beyond that.
- Google rate limiting may contribute to those outliers (many queries were issued in one session) — the owner's
  suggestion; **not shown**. Re-measure with fewer queries if it matters.
- **First-run warning: observed (owner's screenshot), Windows 10.** The installer carries a
  Mark-of-the-Web (added to the downloaded file to stand in for a browser download) and was launched by
  double-click. Windows showed the classic **"Open File - Security Warning"** dialog, *not* the blue
  "Windows protected your PC" screen: **"The publisher could not be verified. Are you sure you want to run this
  software?"**, Publisher **"Unknown Publisher"**, Type Application, with **Run** / **Cancel** and an
  "Always ask before opening this file" box, and the line "This file does not have a valid digital signature
  that verifies its publisher." That is what a first-time user sees; **Run** continues to the installer.
  Not observed: a warning from the browser itself at download time (Edge may add its own "not commonly
  downloaded" prompt); the real browser download was not performed. SmartScreen's cloud reputation check
  was not seen to fire. Signing the installer would turn "Unknown Publisher" into the publisher's name.
- **Windows 11 capture border, the Runtime-missing bootstrapper path and 100/125/200 % scaling on real
  displays remain not verified.**
- This session also found and fixed a Windows-only **test** bug (a `/` literal in an expected path; 154/155 on
  Windows before, 155/155 after) — the suite had never been run on Windows.

## 1. Bottom line (as found, before the fixes)

> **Not ready to merge to `main`.** The app installs, renders PDFs, selects text, and the embedded Google search
> panel works (results load, no CAPTCHA/consent wall). But **it crashes on every quit after a search was used**,
> and because of that the headline privacy promise — *"search data is deleted when you quit"* — is false in practice.

What works (all **verified**): install/uninstall; launch; open via `Ctrl+O` and by file argument; word / phrase /
multi-line selection with the pill; Find meaning via pill, `Ctrl+E` and right-click; panel width ≈ 433 logical px;
panel wheel scroll, typing into the panel, Open in browser; `Esc`/click-document dismissal; full screen (10/10
transitions restore the exact window rect); rotate, zoom, themes, recents, selection colours, page field, About;
size/zoom/page/document persistence; the failure state (simulated).

## 2. Defects, ranked

Each: what, how to reproduce, evidence, **leads** (read from source — hypotheses, not diagnoses), and what "fixed" means.

### D1 — High — crash on quit after a search; profile folder (with browsing data) left behind

- **Observed.** After Find meaning has been used in a session, quitting hangs ≈ 5.4 s then `dndreader.exe` crashes:
  `0xc0000005` in `flutter_windows.dll+0x1551f`, immediately followed by `0xc000041d` (fatal exception in a
  window-procedure callback). `%TEMP%\dndreader-search-<pid>` is **not removed**: ≈ 600 files / 68 MB incl.
  `EBWebView\Default\History`, `Web Data`, `Login Data`, caches. No process holds it.
- **Repro (3/3).** Launch → open a fixture → double-click a word → `Ctrl+E` → wait for results → quit by
  (a) `CloseMainWindow`, (b) a real click on the title-bar X, (c) `Esc` to close the panel *first*, then X.
  **Control:** same session, never opening the panel → exit in 338 ms, no crash, nothing left.
  Abrupt `Stop-Process -Force` also leaves the folder (expected) with no orphaned WebView2 processes.
- **Evidence.** Windows Application log: Application Error + WER (APPCRASH), same fault offset every time; fault
  PIDs matched the sessions (appendix of RESULTS.md). The leftover folder was written to at the instant of the
  click — the profile was live when the process died.
- **Leads.**
  - `lib/features/search/search_web_view_windows.dart` — `AppLifecycleListener.onExitRequested` → `_shutdown()` →
    `_runShutdown()` (`clearCookies`, `clearCache`, `controller.dispose()`, `_profiles.delete()`). Unknown whether
    it runs, how long it takes, or whether the 5.4 s is it timing out. `debugPrint` output only exists in debug
    runs — **run a debug build and read the `[search]` log lines first.**
  - `windows/runner/flutter_window.cpp` `FlutterWindow::OnDestroy()` sets `flutter_controller_ = nullptr`
    (destroys engine + plugin registrar) while the webview plugin's capture/texture and its window-proc delegate
    may still be alive; `0xc000041d` means the fault was inside a WndProc callback. Plausible: a message is
    dispatched to a plugin delegate holding freed state during/after engine teardown.
  - Crash needs a `WebviewController` to have existed; *closing the panel does not help*, so disposal on panel
    close is not releasing whatever faults.
- **Next steps for a fixer.** Capture a dump (WER LocalDumps registry key or `procdump -e 1 -ma`), symbolise
  `flutter_windows.dll` at `0x1551f`; reproduce under a debug build; try destroying the webview controller
  *before* `OnDestroy` (e.g. on `onExitRequested`, await full dispose, then let the runner tear down), and verify
  ordering with the plugin's own teardown.
- **Done when.** Quit after a search exits < 1 s with **no** Application Error event and no
  `dndreader-search-*` left, in all three quit paths above. Add that to the checklist in
  `docs/completion-report-windows.md` §7 step 13 as a hard pass/fail.

### D2 — Medium — stale-profile sweep runs on first search, not at launch

- `_profiles.sweepStale()` is called from the search view's initialisation (`search_web_view_windows.dart`, before
  `_profiles.create()`), so it only runs the first time Find meaning is used in a session. Wording in README,
  `search_profile.dart`, the log line and the About text says "the next launch will sweep it".
- **Verified.** Stale folder still present 10 s after relaunch; removed and replaced by a new pid folder on the
  first search (twice: after a crash, and after a kill).
- **Fix direction.** Sweep once at startup (cheap, guarded by the existing lock/age/pid rules), or correct the
  wording. With D1 fixed this is low urgency, but crashes/kills still depend on it.
- **Status — fixed on Linux-testable code, 2026-10-14 (`fix/d2-sweep-at-launch`, merged as `979aa60`).** Chose
  *behaviour* over wording: the wording ("the next launch sweeps it") was the right promise, the call site was
  wrong. `sweepStaleProfilesAtLaunch()` (`search_profile.dart`) is now called from `main()` after `runApp`
  (`lib/main.dart`), **Windows only**, in a **background isolate** (`Isolate.run`) so a leftover of hundreds of
  files cannot hold up the first frame; it never throws. The sweep in `Webview2SearchWebView.start()` was
  **removed**. Guards untouched: `decideSweep`, `SearchProfileStore.sweepStale`, the lock probe, the 60 s age
  rule, own-pid exclusion.
  - One honest caveat the wording needed: a crashed run that died *before* creating its lock file is only swept
    once 60 s old, so that (rare) leftover goes at "a later launch", not necessarily the next. Comment added in
    `search_profile.dart`; user-facing text ("until the next launch removes it") left as is.
  - **Verified (Linux, how):** 4 new unit tests run `sweepStaleProfilesAtLaunch` end-to-end through the real
    isolate against a temporary directory — disabled → untouched; a stale lock-bearing folder removed; and the
    guards still refuse a lookalike name, a non-owned name, a file, a symlink to an outside directory (its
    contents survive), a folder with a fresh lock-less state, and the own pid. 155 tests pass; release build
    runs; no `dndreader-search-*` created on Linux.
  - **Not verified (needs Windows):** that the isolate really sweeps a real WebView2 leftover at launch (the
    68 MB / ~600-file case), that it runs without noticeable startup cost, that a second live instance's folder is
    skipped via the Windows lock (`lockSync` is non-blocking/exclusive there — **read**), and path-casing/junction
    handling. **Re-verify:** run Find meaning, `Stop-Process -Force`, relaunch and *do not search* — the
    `dndreader-search-<oldpid>` folder should be gone within a few seconds of launch.

### D3 — Medium — spurious "Couldn't load results" and desynced Back after a Cloudflare-gated result

- **Repro.** Find meaning on "efficient"; click a result in the AI Overview that goes to thesaurus.com.
  Panel shows **"Couldn't load results"** (Retry / Open in browser) although the page then loads; the state
  **flaps** between the error overlay and the site's "Performing security verification… Verification successful"
  interstitial and finally the page. Pressing Back several times ends with **the Back arrow disabled while a
  page is displayed** (navigation history and the app's model out of sync). Reproduced twice.
- **Evidence.** `screenshots/06`, `07`, `08`. No network fault existed (Google and the site loaded).
- **Leads.** `controller.onLoadError` → `_onLoadError` in `search_web_view_windows.dart`; only
  `WebErrorStatus.operationCanceled` is filtered. A challenge redirect likely yields another status
  (e.g. connection-reset/redirect-loop class) that the session treats as a hard failure and doesn't clear when the
  next navigation completes. Back enablement is probably derived from the app's own history stack rather than the
  webview's.
- **Done when.** A superseded/challenged navigation never shows the failure overlay if the page ends up loading;
  Back is enabled iff the webview can go back.
- **Constraint.** Do **not** automate or interact with the verification widget itself; observe only.

### D4 — Medium — shortcuts dead after the page field's Enter until the document is clicked

- **Repro.** Click the page field, type `3`, Enter (jumps to page 3 — works). Press `Ctrl+R` / `Ctrl+Shift+R`:
  nothing. Click the document, press `Ctrl+R`: rotates; `Ctrl+Shift+R` restores the exact pixels. The field
  still shows its focus outline after Enter.
- **Leads.** `lib/features/reader/reader_header.dart` `PageField._submit` → `_finish()` →
  `_focus.unfocus()` + `onDone`. Intent is clearly to return focus to the document; on Windows the focus stays
  or goes to a node outside the `CallbackShortcuts` subtree (`reader_screen.dart` ~L405). Possibly
  platform-independent — **Linux parity unknown**; check there before assuming a Windows-only cause.
- **Done when.** After Enter (and after Esc in the field), `Ctrl+R/E/T` and arrow keys act on the document
  without an extra click. Add a widget test.
- **Status — fixed; Linux parity settled: this is a shared bug, not a Windows one (`fix/d4-page-field-focus`,
  merged as `d47c9d1`).**
  - **Reproduced on Linux first.** The real app was run on the Linux device with `flutter test
    integration_test -d linux` (new `integration_test/page_field_focus_test.dart`, `outline.pdf`): after Enter —
    and after Esc — in the page field, `Ctrl+T` did nothing and `primaryFocus` was the route's
    `_ModalScopeState` focus scope. A control (Ctrl+T with no field interaction) passed. **Caveat:** keys are
    injected *inside Flutter* (`sendKeyEvent`), not through GTK; OS-level input cannot be driven on this machine
    (no xdotool/Xvfb; XTest under XWayland does not reach the app, as recorded in M0). The GTK→engine hop is
    therefore untested, but this bug is entirely above it.
  - **Cause (from the focus tree, confirmed by the reproduction).** The page field sits *under* the reader's
    `Focus(_readerFocus)`. `_finish()` runs `_focus.unfocus()` (default `UnfocusDisposition.scope`, applied on a
    microtask) and then `onDone` → `_focusReader()`, whose guard `!_readerFocus.hasFocus` is **still true** —
    `hasFocus` includes descendants and the unfocus has not applied — so it does nothing. Primary focus then
    settles on the enclosing focus scope, which is *above* `CallbackShortcuts`. Shortcuts and the viewer's own
    arrow-key handling both miss it until a click gives the viewer focus. (The still-visible focus outline on
    Windows after Enter is not explained by this and was not reproduced on Linux — see below.)
  - **Fix.** `ReaderScreen._onPageEditDone()` (`reader_screen.dart`, new method next to `_focusReader`; the
    header is now wired to it): when a document is ready it calls `PdfViewerController.requestFocus()` — the
    same node a click on the document focuses — else falls back to `_readerFocus.requestFocus()`. `_focusReader`
    (used when the search panel closes) is **unchanged**.
  - **Verified (Linux, how):** the integration run above — **fails 3/4 before the fix** (Enter, Esc, and "focus
    lands on the same node as a click on the document"), **passes 4/4 after**; `Ctrl+T` toggles the contents
    panel after both exits. Plus two widget tests (`test/widget/page_field_focus_test.dart`) covering both exits
    on the same tree shape. **Honest limit of the widget tests:** pdfrx cannot start inside `flutter test`, so
    they exercise `PageField` and the focus contract, and would pass without the `reader_screen.dart` change;
    the regression guard for the wiring is the integration test, which CI does not run (no display).
  - **Not verified (needs Windows):** that this fixes the Windows symptom. Same code path, so it is expected
    to, but Windows showed an extra symptom (the field kept its focus outline after Enter) that I could not
    reproduce on Linux. If `Ctrl+R` is still dead after Enter on a build of this branch, treat it as a *new*,
    Windows-specific focus problem (candidates: the field's own `unfocus()` on Windows, or the embedder's text
    input), not as D4 again.

### D5 — Medium — default first-run window is taller than the work area at 150 % scale

- **Observed.** No `window-size` file → default 1100×760 logical → `GetWindowRect` `15,15 1650×1106` on a
  1920×1080 screen whose work area is 1034 px tall. ≈ 87 px of window sits under the taskbar; the lower part of
  the document and a selection pill near the bottom are hidden (`screenshots/04`).
- **Leads.** `windows/runner/main.cpp` passes the logical size straight to `Win32Window::Create`, which scales by
  the monitor DPI (`win32_window.cpp` ~L134–140); there is no clamp to the monitor **work area** after scaling.
  (The CI smoke test's `1044 760` was clamped only because the virtual display was small.)
- **Done when.** The first-run window always fits inside the monitor work area at 100 %, 125 %, 150 %, 200 %;
  the saved size is still stored in logical px.

### D6 — Low — polish

Default Flutter icon (title bar, taskbar, Open With); Open With lists `dndreader` lower-case (set
FileDescription / `FriendlyAppName`); Uninstall entry has an empty Publisher.

### D7 — Low — uninstall leftovers

After uninstall: `HKCU\Software\Classes\Applications\dndreader.exe` (`shell\open` empty, `SupportedTypes\.pdf`)
remains because only the `shell\open\command` key has `uninsdeletekey` in `packaging/windows/dndreader.iss`
(lines 62–63); `%APPDATA%\dndreader\window-size` and `%APPDATA%\com.dndreader\dndreader\shared_preferences.json`
remain (acceptable for user settings, but should be a decision, not an accident). A killed/crashed session's
`%TEMP%\dndreader-search-<pid>` also survives uninstall.

## 3. The three risks the previous session flagged

| Risk | Result | Evidence |
|---|---|---|
| **Focus** (package-reported bouncing) | **Not reproduced.** Typing into the panel after a click works; click-document closes the panel (by design, `implementation-plan.md` L337) and arrows scroll the document; `Esc` after clicking in the panel closes it; shortcuts work immediately after close. The one focus defect is D4. | `screenshots/09`, `10` |
| **Wheel constant** (`1.0` derived, not measured) | **Measured:** `WheelScrollLines = 3`; one notch = **171 physical px = 114 logical px at 150 % scale**, identical in 6/6 samples (≈ 14 % above the ~100 px target). Not measured at 100 % scale; a 5-notch burst could not be matched reliably. `Ctrl`+wheel zoom works and restores exactly. | method: pixel cross-correlation of consecutive screenshots |
| **Full screen** (synthesised `fullscreenChanged`) | **Works.** `F11`↔`Esc` ×4, `F11` toggle, header icon in/out ×2, icon-in/`Esc`-out, `F11`-in/icon-out: 10/10; each restore returned exactly `15,15 1650×1106`. Full screen covers the taskbar; the panel renders in full screen; `Esc` leaves full screen first, then the panel (matches `_escape` in `reader_screen.dart`). | `screenshots/12`, `13` |

## 4. Other verified facts

- **Runtime:** `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
  `pv` = `155.0.4283.45`; native HKLM and HKCU keys absent.
- **Process tree (panel open):** `dndreader.exe` → `msedgewebview2.exe` (browser) → gpu ×1, utility ×4,
  renderer ×3, crashpad ×1. Command line has `--user-data-dir=%TEMP%\dndreader-search-<pid>\EBWebView`,
  **no `--no-sandbox`** on any child. Sandbox integrity level itself: **not verified**.
- **Install:** per-user (`%LOCALAPPDATA%\Programs\DNDReader`, 21 files, ≈ 40 MB, no `libcef`), no UAC;
  ProgId `DNDReader.pdf`, `.pdf\OpenWithProgids`, `Applications\dndreader.exe` registered; default `.pdf` handler
  not changed. Uninstall: exit 0 in 2 s.
- **Open with / argument:** the Open With list contains the app; `dndreader.exe "<pdf>"` (the registered
  command) opens the file. (The `rundll32 OpenAs_RunDLL` route passed a trailing-space path and the app showed
  the previous document — inconclusive; a real Explorer right-click was **not** performed.)
- **Search panel / Google:** results loaded every time, in-app, with no CAPTCHA and no consent wall (this
  machine's region). The only interstitial seen was Cloudflare's on thesaurus.com (D3), not Google's.
- **Failure state:** simulated with a dead local proxy via `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=
  --proxy-server=127.0.0.1:9` (documented WebView2 mechanism) — shows "Couldn't load results", Retry,
  Open in browser. A real network disconnect was **not** done.

## 5. Not verified

Windows 11 yellow capture border (Windows 10 here — **cannot be ruled out**); SmartScreen as a real first-time
user sees it (a synthetic Mark-of-the-Web produced none; the owner ran the installer by hand and has not yet
reported what appeared); Runtime-missing bootstrapper path; per-machine install; EEA/UK consent wall; 100 %
display scaling for any measurement; a real disconnect; real Explorer right-click → Open with; sandbox integrity
level; whether `onExitRequested` actually runs (D1 root cause).

## 6. Rules the owner set (keep them)

- **Never commit, merge or open a PR to `main`** — the owner merges. Work on branches off `feat/windows-port`,
  **one branch per fix**, `--no-ff` merge back, keep the **149 tests** passing and CI green.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (match existing history).
- **Never** automate Google, scrape or parse result HTML, or aim synthetic input at a CAPTCHA/verification
  widget — screenshot, note what triggered it, move on. Use only `test_fixtures/*.pdf`.
- No AI, no API keys, no backend, no telemetry. Label every claim verified / read / not verified; never report
  as executed what was not run.
- Fixing needs Flutter **3.47.7** and Visual Studio C++ build tools on a Windows machine — the owner's decision
  to install; CI (`windows.yml`) can build without them but cannot show a screen.

## 7. Suggested order of work

1. **D1** (merge blocker) — reproduce under a debug build, get a dump, fix teardown ordering, prove with the
   three quit paths + Application-log check.
2. **D3**, **D4**, **D5** — each its own branch with a test where one is possible
   (D4 widget test; D5 a pure clamp function with unit tests like `window_settings`).
3. ~~**D2**~~ — done on Linux-testable code (see D2); re-verify on Windows. ~~**D4**~~ — shared bug, fixed; re-verify on Windows.
4. **D6/D7** — installer/icon polish in `packaging/windows/`.
5. Re-run the whole §7 checklist on a build from CI, and get the owner's SmartScreen observation and a
   Windows 11 pass for the capture border.

## 8. Reproducing this run

Download the artifact `dndreader-windows-installer` from the Actions run above (needs GitHub auth; artifacts
are not public). Run it, then dot-source `tools/input-helpers.ps1` and drive the app. Hard-won gotchas are
in that file's header (scan codes, `Move` alias, DPI awareness, foreground stealing). Crash events:
`Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error'} | ? Message -match dndreader`.

## 9. Linux regression pass on the shared changes (Ubuntu session, 2026-10-14)

Closes the gap flagged in `ORCHESTRATOR-HANDOFF.md` §4.3: the D1/D3 fixes changed shared Dart and the Linux app
had not been launched since. Test file: `integration_test/linux_regression_test.dart` (run with
`LINUX_REGRESSION=online|offline|gated|quit flutter test integration_test/linux_regression_test.dart -d linux`).

**How (and its limits).** The real Linux app with the real CEF webview and the real network, driven by
pointer/key events injected *inside Flutter*. The CEF browser ran **unsandboxed** (the dev override on a debug
build — the release bundle fails closed without the installed AppArmor profile, which needs root), so the
sandbox/fail-closed path was **not** exercised. OS-level input still cannot be driven here; the window close for
the quit check was a real `WM_DELETE_WINDOW` sent over X11 (`GDK_BACKEND=x11`), which is what the title-bar X
sends. "Offline" was simulated with a dead proxy (`https_proxy=http://127.0.0.1:9`, loopback exempt), not by
pulling a cable.

### Found and fixed: a genuine Linux regression from the D3 change

- **Reproduced.** Offline, Find meaning produced `loadError -130 ERR_PROXY_CONNECTION_FAILED`, then — in the
  same instant — the panel went to `loaded`. The failure was swallowed.
- **Cause.** CEF raises `OnLoadEnd` for the *failed* URL right after `OnLoadError`. The D3 session rule "a page
  that completes after a failure recovers from `failed`" (`search_session.dart`, `_handleLoadEnd`) read that
  trailing end as the page loading. On Windows the view already drops the trailing `NavigationCompleted`
  (`_navigationFailed`), so it never arose there; the CEF view had no equivalent.
- **Fix.** `FailedLoadEndFilter` (`search_web_view.dart`) used by `CefSearchWebView`: the load-end for exactly the
  failed URL is not forwarded, once; any new navigation (`loadUrl`/`goBack`/`reload`) clears the pairing. The
  session logic, and therefore the Windows behaviour, is unchanged. Three unit tests for the filter.
- **Verified after the fix (Linux, offline):** failure shown in **723 ms**; still `failed` 10 s later; a refused
  loopback connection fails in 145 ms and **Retry succeeds once the server is up**. Before the fix the same run
  never observed `failed`.
- Note that the existing unit test "a page that finishes loading after a failure recovers from it" is the rule
  that exposed this; it stays correct for engines that do not raise a trailing end.

### Verified unchanged on Linux (real app)

| Check | Result |
|---|---|
| Open `prose.pdf`, select a word, `Ctrl+E` | Results loaded in ~1.1 s, Google, `canGoBack` false |
| Two in-panel navigations, Back ×2 | `canGoBack` true, true, then Back → previous page, then Back → search page with `canGoBack` false: enabled state matched in every step |
| Open in browser | Reported the page being shown (opener injected — a real `xdg-open` was **not** launched) |
| Close panel | Document `visibleRect` identical before/after, scrolled to page 2 (not at the top) |
| Error grace | The 5 s grace **does not govern CEF**: its ambiguous set is WebView2's names (`unknown`, `connectionAborted`, `redirectFailed`); CEF reports `ERR_*` strings, so every CEF error fails immediately (observed: 723 ms offline). **Read** from the CEF fork + observed |
| `AppShutdown.install()` | Inert on Linux: no hook is ever registered by the CEF path, and its channel (`dndreader/lifecycle`) is not the runner's `dndreader/window`. Full screen/quit unaffected. **Read**; the quit result below is the behavioural check |
| Quit after a search | Close request → 8 `dndreader` processes (main + CEF children) → 0 in **0.3 s**; no hang, no crash |
| CEF "in-memory" claim | Nothing from this session's searches (terms, `example.com`, `iana.org`) appears anywhere under `~/.config/cef_user_data`; `Cookies`/`History`/`Login Data` there date from the first CEF initialisation and were not modified. **Caveat:** that directory *is* the CEF root cache and is written with browser metadata (Preferences, Local State, empty DB schemas, 122 MB of component data from earlier runs), and each run leaves a `/tmp/org.chromium.Chromium.*` socket directory behind. Neither contains search data; both predate this work, and the README's "cookies and storage in memory" claim is about search data |

### Back divergence — decision: **deliberate, documented; no CEF change**

- **Windows** (D3): Back follows the webview's own history (`historyChanged`), because WebView2 replaced
  entries on challenge hops and the Dart-side list desynced.
- **Linux**: Back still comes from the session's own list and calls CEF `goBack()` (CEF is not asked for its
  history state: `onHistoryChanged` is a no-op).
- **Evidence it is not desynced on Linux:** in the step table above Back's enabled state and destinations
  matched across 3 navigations; and in a separate observation run, `thesaurus.com` (the D3 site) loaded from the
  results page in ~5 s with **no failure overlay and no flapping**, `canGoBack` true, and Back returned to the
  results page and disabled itself (further Back presses were correctly inert).
- **Limits of that evidence:** the Cloudflare interstitial **did not appear** on this network, so the scenario
  that desynced Windows was not actually reproduced on Linux; navigations were programmatic (`loadUrl`), not
  link clicks. If Linux ever shows the desync, port the same `historyChanged` hook to the CEF view (the session
  already supports it) — the cost is small.
- **Why not port it now:** it would be an untestable change to a path that works in every observed case, and
  CEF's history-change reporting in the pinned fork was not read or exercised.

### Not verified (this pass)

The sandboxed/fail-closed path (no root for the AppArmor profile); a real network disconnect and reconnect;
real link clicks inside the panel; the Cloudflare gate on Linux; Wayland-native input; the `.deb`; anything on
Windows.
