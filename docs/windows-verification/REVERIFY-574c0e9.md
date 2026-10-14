# Windows re-verification of D4 and D2 — `feat/windows-port` @ `574c0e9`

Written for: the owner and the next Claude session (the one that will fix D1/D3/D5/D6/D7), as the answer to the
"what you must re-verify on Windows" list in `HANDOFF-windows-session.md`. Docs only; **no source changed**.

- **Build under test:** CI run `38532082742` (green), artifact `dndreader-windows-installer`,
  sha256 `13f4c3cce781600f437c924f9d30f96566f3d5c2b766b2cd6a68e00ca4a2c179`, installed silently per-user.
- **Machine:** Windows 10 22H2 (19045), 1920×1080 at 150 %, WebView2 Runtime 155.0.4283.45.
- **Method:** same as `REPORT.md` — ordinary synthetic mouse/keyboard input on the installed app, screenshot pixel
  diffs, process/registry/filesystem/event-log inspection. Only `test_fixtures/*.pdf` opened.
- Labels: **verified** = observed on the running app; **not verified** = not run.

## Result

| Item | Result |
|---|---|
| **D4** — shortcuts after page-field Enter / Esc | **Fixed on Windows. Verified.** |
| **D2** — stale profile swept at launch | **Fixed on Windows. Verified.** |
| D2 side conditions (live instances, startup cost) | **Verified.** |
| **D1** — crash on quit after a search | **Still present, unchanged.** Same fault, same offset. |
| Handoff item 3 (launch sweep must not mask D1) | **Not performed** — needs a D1 fix first. |

## D4 — page field → shortcuts, no click

Fixture `prose.pdf`, window `1200×799`. Each step is a single synthetic key press with **no click** in between;
"changed" is the percentage of sampled pixels in the document area that differ by more than 20/255.

| Path | Action | Result |
|---|---|---|
| Enter | field → `2` → Enter (page jumped) | — |
| | `Ctrl+T` | contents panel opened (35.2 % changed) |
| | `Ctrl+T` | closed, **0.0 %** vs before (pixel-identical) |
| | `Ctrl+R` | rotated (17.1 %) |
| | `Ctrl+Shift+R` | restored, **0.0 %** vs before |
| | `↓` ×4 | document scrolled (15.0 %) |
| Esc | field → type `3` → `Esc` (value reverts to the real page) | — |
| | `Ctrl+T` open / close | 36.0 % / **0.0 %** restored |
| | `Ctrl+R` / `Ctrl+Shift+R` | 14.6 % / **0.0 %** restored |

Before the fix (`a4dfa20`) `Ctrl+R`/`Ctrl+Shift+R` produced **0.0 %** change after Enter. Now they act.

**Correction to `REPORT.md` D4.** The first run recorded that "the field still shows its focus outline after
Enter". That was a **misread**: the mouse pointer was still hovering over the field, which gives a grey hover
border. The real focus state (teal outline + caret) appears only while typing — see the
re-verification capture (typing | after Enter | after Esc, with the pointer still over the field; the image was
removed from the repository). So there is **no** Windows-specific focus residue; D4 was the shared bug the Linux session fixed.

Not exercised: `Ctrl+E` immediately after Enter (needs a selection, and selecting requires a click on the
document, which is the very thing D4 is about) — covered on Linux by the integration test.

## D2 — sweep at launch

| Scenario | Result |
|---|---|
| Use Find meaning (profile with 256 files + lock), `Stop-Process -Force`, relaunch **without searching** | Old `dndreader-search-<oldpid>` **gone 2.9 s after launch**, although it was under 60 s old (it had a stale lock). |
| Three live instances A, B, C (A and B had searched) + a fourth instance launched | **A's and B's folders and processes untouched.** (C never searched, so it has no folder.) |
| D killed while A/B/C live, then instance E launched | D's folder **removed in 3.5 s**; A's and B's **kept**. |
| Startup cost with leftovers (2 stale folders, 38.7 MB) | window shown in **1999 ms**; with no leftovers **1889 ms and 1993 ms**. No measurable slowdown. |

## D1 baseline on this build

Find meaning → close nothing → real click on the title-bar X: quit **5.48 s**, then `0xc0000005` /
`0xc000041d` at `flutter_windows.dll+0x1551f` (two Application Error events, same offsets as `a4dfa20`), and
`%TEMP%\dndreader-search-<pid>` left behind. D2's launch sweep does not change this — it removes the leftover on
the *next launch*, which is a recovery, not a fix. Handoff item 3 (confirm a normally quit session is deleted by
the shutdown path rather than the sweep) can only be checked after D1 is fixed.

## Still open / environment

- **D1, D3, D5, D6, D7 remain.** D6 re-checked trivially: `FileDescription` is still `dndreader`.
- **This machine has no Flutter, Dart, CMake or Visual Studio C++ tools** (checked: none on `PATH`, no `vswhere`).
  The hand-off says to stop and tell the owner in that case; installing them is the owner's decision.
- Not verified, unchanged: Windows 11 capture border; SmartScreen as the owner saw it; Runtime-missing
  bootstrapper; 100 % scaling; a real network disconnect.
