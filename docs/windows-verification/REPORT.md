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

## 1. Bottom line

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
3. **D2** — sweep at startup or fix wording; fold into D1's branch only if trivial.
4. **D6/D7** — installer/icon polish in `packaging/windows/`.
5. Re-run the whole §7 checklist on a build from CI, and get the owner's SmartScreen observation and a
   Windows 11 pass for the capture border.

## 8. Reproducing this run

Download the artifact `dndreader-windows-installer` from the Actions run above (needs GitHub auth; artifacts
are not public). Run it, then dot-source `tools/input-helpers.ps1` and drive the app. Hard-won gotchas are
in that file's header (scan codes, `Move` alias, DPI awareness, foreground stealing). Crash events:
`Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error'} | ? Message -match dndreader`.
