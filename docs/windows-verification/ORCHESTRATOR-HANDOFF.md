# DNDReader Windows port — hand-off to an orchestrator session

Written for: **an orchestrator / reviewer Claude session** taking over after the Windows verification and fix
sessions. Self-contained; assumes no memory. Longer evidence: [REPORT.md](REPORT.md), [RESULTS.md](RESULTS.md),
[REVERIFY-574c0e9.md](REVERIFY-574c0e9.md). Labels: **verified** (observed on a running build), **read**
(source/docs), **not verified**.

## 1. State in one paragraph

`feat/windows-port` (head **`625de1e`**; last code commit `893d321`, CI **green**, run `38545084438`) contains
the Windows port **plus fixes for all seven defects (D1–D7)** found when the app was first run on a real
Windows 10 machine. `main` is untouched at `f0bc24d`; **merging to `main` is the owner's decision**. The only
unverified items are environmental (Windows 11 border, a true browser download, other display scales).

## 2. What was wrong and what changed

| # | Defect found | Fix (branch) | Evidence |
|---|---|---|---|
| D1 | Quit after a search hung ~5 s, crashed (`0xc0000005`/`0xc000041d`, `flutter_windows.dll`) and left `%TEMP%\dndreader-search-<pid>` (history, login DBs) behind — the "deleted when you quit" promise failed | `fix/d1-quit-crash`: runner defers `WM_CLOSE`, asks Dart to run shutdown hooks over channel `dndreader/lifecycle` (`prepareToClose`), closes on reply or a 6 s native backstop; new `lib/services/app_shutdown.dart`; search view registers its clear/dispose/delete as a hook. Root cause: the runner's `WM_CLOSE` went straight to `DestroyWindow` (47 ms), the engine never sent an exit request so `onExitRequested` never ran, and WebView2 was torn down inside `OnDestroy()` | **Verified** debug + release: X-click, `Esc`→X, `CloseMainWindow` → 0 Application Error events, folder gone, ~0.5–0.8 s |
| D2 | Stale-profile sweep ran at first search, not launch | Ubuntu session (`fix/d2-sweep-at-launch`) | **Re-verified on Windows** (`REVERIFY-574c0e9.md`): removed ~3 s after launch, live instances untouched, no startup cost |
| D3 | Cloudflare-gated result showed "Couldn't load results" over a loading page; Back desynced | `fix/d3-load-error-and-back`: pair an error with its own `NavigationCompleted`; hold ambiguous errors (`unknown`, `connectionAborted`, `redirectFailed`) 5 s; recover from `failed` when the page loads; ignore `__cf_chl_*` hops in history; Back uses browser `goBack()` when it can, else reloads our previous page; new `SearchWebView.onHistoryChanged` | **Verified** on real app (dictionary.cambridge.org, thesaurus.com); real status logged: `unknown` (0). 9 session tests |
| D4 | Shortcuts dead after page-field Enter/Esc (shared bug, not Windows-specific) | Ubuntu session (`fix/d4-page-field-focus`) | **Re-verified on Windows** by pixel diff |
| D5 | First-run window 1650×1106 at 150 % on 1080p (work area 1034): bottom under the taskbar | `fix/d5-window-fit-work-area`: header-only `FitToWorkArea()` applied after DPI scaling in `Win32Window::Create`; 10 logical px margin | **Verified** real first run `1650×1004`; 184-check MSVC test in `windows/runner/test/`, **also run in CI** |
| D6 | Flutter default icon, `dndreader`, no publisher | `fix/d6-d7-branding-and-uninstall`: icon rendered from `packaging/linux/deb/dndreader.svg`; `FileDescription`/`ProductName` DNDReader; `AppPublisher`/company `thisisankit27` (the .deb maintainer); `FriendlyAppName` | **Verified** title bar, taskbar, Open With, uninstall entry |
| D7 | Uninstall left `Applications\dndreader.exe`, settings, stray profiles | same branch: `uninsdeletekey` on the whole key; `[UninstallDelete]` removes `%APPDATA%\dndreader`, `%APPDATA%\com.dndreader`, `%TEMP%\dndreader-search-*` | **Verified**: seeded a stale profile, uninstall removed all; default `.pdf` handler untouched |
| – | Test suite had never run on Windows: 154/155 (a `/` literal in an expected path) | `fix/test-profile-path-separator` | 155/155; now **170** |

Process note: all fixes are separate branches merged `--no-ff`; one CI-yaml repair of the D5 step went straight
onto `feat/windows-port` (`66b3567`).

## 3. Verification, honestly

- **Where:** Windows 10 22H2, 1920×1080 at **150 %**, WebView2 Runtime 155.0.4283.45. Local **debug and release**
  builds, plus the CI-built installer for the earlier re-verification. Driven with ordinary synthetic
  mouse/keyboard input; evidence by screenshots, pixel diffs, process/registry/filesystem/Event Log.
- **Gates:** `dart format`, `flutter analyze`, **170 tests**, CI (`analyze_test`, `build_windows` incl. geometry
  test, bundle assertions, installer build, silent install/launch/uninstall smoke test) — all green.
- **Measured wheel notch** (the "calculation, not measurement" risk): 171 physical px = 114 logical px per
  notch at 150 % with `WheelScrollLines=3`, identical in 6/6 samples (≈14 % above the ~100 px target).
  Not changed. Not measured at 100 %.
- **Full screen:** 10/10 transitions (F11/Esc/header icon/mixed) restore the exact rect. **Focus bouncing: not
  reproduced.**
- **First-run warning (owner's screenshot):** with a Mark-of-the-Web the installer shows Windows' *Open File –
  Security Warning* ("publisher could not be verified", **Unknown Publisher**, Run/Cancel) — not the blue
  SmartScreen screen. A true browser download was not performed. Installer is unsigned.

## 4. Residuals and open items

1. **Quit with a heavy live Google page is not always sub-second.** 11 live release quits: 8 took 0.55–0.75 s,
   3 took 2.5 / 3.4 / 8.0 s (a leftover folder followed the slow ones; the next launch's sweep removed it). With
   no network (dead proxy) 6/6 took ~0.67 s. The slow step is `SearchProfileStore.delete()` — up to 10×300 ms
   retries on a synchronous `deleteSync` while WebView2's browser process exits. Bounded and recovered, **not
   eliminated**. Possible follow-up: async delete / wait for browser exit. Google rate limiting may contribute
   (the owner's suggestion; not shown).
2. **Not verified:** Windows 11 capture border (needs a Win 11 PC); Runtime-missing bootstrapper path; per-machine
   install; EEA/UK consent wall; 100/125/200 % on real displays (D5 is covered by the pure test only);
   sandbox integrity level (no `--no-sandbox` flag seen on any child); a real network disconnect (simulated).
3. **Linux not re-run.** The D3 session/interface changes are shared Dart; the Linux tests pass in CI and
   locally, but the **Linux app was not launched** after these changes (CEF's `onHistoryChanged` is a no-op, so
   its Back path is unchanged by design). Worth one manual Linux pass before release.
4. **Owner decisions taken on their behalf (revisit if disliked):** uninstall deletes `%APPDATA%` settings (they
   hold recent-file paths); publisher string `thisisankit27`; icon reuses the Linux artwork; error grace 5 s.
5. **Review hot-spots:** `flutter_window.cpp` `WM_CLOSE` deferral (a second close while pending is ignored;
   `WM_ENDSESSION` is not specially handled); `search_session.dart` heuristics (`__cf_chl_` substring, the
   ambiguous-error set); `[UninstallDelete]` also removes a *live* instance's temp profile if one is running
   during uninstall.
6. **Legacy items from the original report still open:** repository has no `LICENSE`; code signing; the
   low-adoption `webview_flutter_windows` dependency review; whether to upstream the `webview_cef` fork change.

## 5. Environment and tooling left on the machine

- Flutter 3.47.7 at `C:\src\flutter`; VS Build Tools 17.14 (VC workload); Inno Setup 6.7.3 per-user.
- `docs/windows-verification/tools/input-helpers.ps1` — synthetic input + screenshots; gotchas in its header
  (scan codes, DPI awareness, `Move` alias, foreground stealing). **Compute the X-button position from the
  window rect**; the saved window size changes it.
- Quit-timing without Google traffic: `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--proxy-server=127.0.0.1:9`.
- Untracked local-only: `verification/` (full-size captures), `dist/`, the WebView2 bootstrapper (all
  gitignored). A copy of the CI installer is kept outside the repository.

## 6. Rules to keep

Never commit/merge/PR to `main`. One branch per fix off `feat/windows-port`, `--no-ff`, keep tests/format/
analyze/CI green, trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. **The repo is public:**
do **not** commit screenshots (the earlier set was removed before merge); scan for the username/email/personal paths first. Use only
`test_fixtures/*.pdf`. Never automate Google or aim input at a CAPTCHA/verification widget. No AI/keys/backend/
telemetry. Label every claim verified / read / not verified.

## 7. Suggested next actions

1. Owner: review and merge `feat/windows-port` → `main` (or ask for changes).
2. Optional hardening: item 4.1 above; a Linux smoke pass (4.3); a Windows 11 check (4.2).
3. Release hygiene: `LICENSE`, decide on code signing, README note about the unsigned-installer warning.
