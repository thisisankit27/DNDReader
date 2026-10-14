> **Historical.** This prompt was consumed; D1–D7 are fixed. Current state: `ORCHESTRATOR-HANDOFF.md`.

# Hand-off prompt — Windows session (D1, D3, D5, D6, D7)

Paste everything below the line into a fresh Claude Code session **on the Windows machine**.

---

# DNDReader — Windows session: fix D1, D3, D5, D6, D7

Fresh session; assume no memory of prior work. You are on **Windows 10/11** with Flutter **3.47.7** and Visual
Studio C++ build tools (confirm both before starting; if missing, say so and stop — installing them is the
owner's decision).

## Orient

```
cd <repo>   # DNDReader
git fetch origin
git checkout feat/windows-port && git pull
```

- `main` = `f0bc24d`. **Never commit, merge or PR to `main`** — the owner merges.
- **`feat/windows-port` = `979aa60`** (or later) — the port **plus** two Ubuntu-session fixes (below).
- Read **`docs/windows-verification/REPORT.md`** in full first: D1–D7 each with repro, evidence, leads and a
  "done when". Its §6 rules are yours too: one branch per fix off `feat/windows-port`, `--no-ff` merge back,
  keep the tests passing (**155**, was 149) and CI green, commit trailer
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, only `test_fixtures/*.pdf`, no AI / keys /
  backend / telemetry, never automate Google or aim input at a CAPTCHA, label claims
  **verified / read / not verified**.

## What the Ubuntu session already changed — do not redo it, do re-verify it

| Defect | Status | Where (file, region) |
|---|---|---|
| **D4** shortcuts dead after page field Enter/Esc | **Fixed — and it was *not* Windows-specific.** Reproduced on the real Linux app (`flutter test integration_test -d linux`); **stop treating it as a Windows bug.** Cause: the page field is under `Focus(_readerFocus)`, so `_focusReader()`'s `hasFocus` guard was a no-op, and the field's own `unfocus()` parked focus on the route scope *above* `CallbackShortcuts`. | `lib/features/reader/reader_screen.dart`: new `_onPageEditDone()` (next to `_focusReader`) and the one-line `onPageEditDone:` wiring in `build`. `integration_test/page_field_focus_test.dart` (new), `test/widget/page_field_focus_test.dart` (new). |
| **D2** sweep ran on first search, not at launch | **Fixed** (behaviour, not wording). `sweepStaleProfilesAtLaunch()` runs from `main()` after `runApp`, Windows-only, in a background isolate; never throws. | `lib/main.dart` (import + one `unawaited(...)` after `runApp`); `lib/features/search/search_profile.dart` (imports + a new function **appended at end of file**; guards untouched); **`lib/features/search/search_web_view_windows.dart`: only `start()` changed — the 6-line `_profiles.sweepStale()` try/catch block was replaced by a one-line comment** (git region `@@ -60,6 +60 @@`). |

**Merge note for D1:** the Ubuntu session touched `search_web_view_windows.dart` only in `start()`, between
the `getWebViewVersion()` check and `_profiles.create()`. Your D1 edits belong in `_runShutdown()` /
`_shutdown()` / `dispose()` and the `onExitRequested` listener at the bottom of the file — no overlap expected.

### What you must re-verify on Windows after these changes (I could not)

1. **D4:** page field → type `3` → Enter → `Ctrl+R`, `Ctrl+Shift+R`, `Ctrl+E`, `Ctrl+T`, arrow keys act with
   **no click**; repeat with `Esc` in the field. REPORT noted the field kept its focus *outline* after Enter on
   Windows — I could not reproduce that on Linux. If shortcuts are still dead, it is a **new Windows-specific**
   focus bug: look at the field's `unfocus()` and the embedder's text input, not at the code above.
2. **D2:** use Find meaning, `Stop-Process -Force`, relaunch, **do not search**: the old
   `%TEMP%\dndreader-search-<oldpid>` must be gone within a few seconds of launch; a *second live* instance's
   folder must be left alone (open two windows, relaunch a third); startup must not feel slower with a 68 MB
   leftover present.
3. After your D1 fix, confirm the launch sweep still leaves a **normally quit** session's folder deleted by the
   shutdown path (not by the sweep) — i.e. don't let D2 mask D1.

## Your scope

Work in the order of REPORT §7 (D1 first):

- **D1 — merge blocker.** Crash on quit after a search + leftover profile with browsing data. Get a dump
  (WER LocalDumps or `procdump -e 1 -ma`), symbolise `flutter_windows.dll` at `0x1551f`, reproduce under a
  **debug** build and read the `[search]` log lines first (does `onExitRequested` run? how long does
  `_runShutdown` take? is 5.4 s a timeout?). Leads: tear the webview down *before* `FlutterWindow::OnDestroy()`
  destroys the engine; await full dispose in `onExitRequested`. Done when quit after a search exits < 1 s with
  no Application Error event and no `dndreader-search-*` left, in all three quit paths (`CloseMainWindow`, real
  title-bar X, `Esc` then X). Add that as a hard pass/fail to `docs/completion-report-windows.md` §7 step 13.
- **D3.** Spurious "Couldn't load results" and desynced Back after a Cloudflare-gated result. Log the real
  `WebErrorStatus` values first (only `operationCanceled` is filtered today); make Back follow the webview's
  own history (`historyChanged`/`canGoBack`), not the app's stack. **Observe only** — do not interact with the
  verification widget.
- **D5.** First-run window taller than the work area at 150 %. Add a **pure clamp function** (with unit tests
  in the style of `window_settings`) applied after DPI scaling in `windows/runner/main.cpp`/`win32_window.cpp`;
  saved size stays in logical px. Check 100 %, 125 %, 150 %, 200 %.
- **D6.** Icon (title bar, taskbar, Open With), `FileDescription`/`FriendlyAppName` = "DNDReader", Publisher
  in the uninstall entry.
- **D7.** `uninsdeletekey` on the whole `Applications\dndreader.exe` key (`packaging/windows/dndreader.iss`
  ~L62–63); *decide* — and document — whether `%APPDATA%` settings survive uninstall.

Do **not** change `lib/features/reader/reader_screen.dart`'s `_onPageEditDone` or the launch sweep's guards
without telling the owner why.

## Done / report

Re-run the whole `docs/completion-report-windows.md` §7 checklist on a **CI-built** installer and update
`docs/windows-verification/REPORT.md` per defect (what changed, what you verified and how, what remains).
Get the owner's SmartScreen observation and, if possible, a Windows 11 pass for the capture border. Stop at
"ready for review"; the owner merges.
