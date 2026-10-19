# Android: what to install and what to test

## Install

Android **8.0 or later** (API 26+). Sideload the APK; no Google Play account is involved.

1. Get `app-arm64-v8a-release.apk` (almost every phone since 2017; `armeabi-v7a` for an old 32-bit one) from the latest green
   **android** workflow run (*Actions* -> *android* -> the run -> artifact `dndreader-android-arm64-apk`; **debug-signed**, for testing) or, for a
   properly signed build, from `android-release` (see [android-release.md](android-release.md)).
2. Copy it to the phone and open it (allow "install unknown apps" for your file manager or browser when asked), or
   `adb install -r app-arm64-v8a-release.apk`. A debug-signed build and a release-signed build have different signatures:
   uninstall one before installing the other.
3. The app asks for no permission. Its one declared permission is `INTERNET` (shown in App info; no prompt).

Use only `test_fixtures/*.pdf` or a PDF you are happy to open.

## What was verified, on one Moto G60 (Android 12, system WebView 149) and an API 36 emulator

See the Android sections of [progress.md](progress.md). In short: opening from the picker and from "Open with"/"Share" (cold, warm, a
second one while reading); touch selection with handles and magnifier; Find meaning in the bottom sheet and the side panel (landscape); the
document untouched after the panel closes; layered Back; full screen; rotation mid-search; offline and Retry; restoration after the
process was killed; the privacy folder being deleted at launch; cold start 1.06 s median, a 240-page file open in about 1.3 s, smooth
scrolling, **memory over budget** (about 520 MB with the browser alive).

## What only you can check

1. **TalkBack.** Turn it on. Does the header read sensibly (Contents, the page number as one control, Zoom, Open, Menu)? Is the **Find meaning**
   button announced once as a button after a long-press selection? Can you reach the search panel's Back / Open in browser / Close, and resize
   the sheet with the "Search results size" increase/decrease actions? (Not run by the author.)
2. **Pinch to zoom** with two fingers, then select text while zoomed: the pill follows. (Zoom buttons and a programmatic zoom were checked, not the gesture.)
3. **A Bluetooth keyboard:** `Ctrl+E`, `Ctrl+T`, `Ctrl+R`, `Ctrl+0`, `F11`, arrow keys, `Esc`. Then a **mouse** (wheel, drag-select, right-click menu) and, if you have
   one, a **stylus**. (Key events were driven through the engine, not from real hardware.)
4. **Open from other apps:** "Open with" from your file manager and from Chrome's downloads; "Share" a PDF from Gmail and from Drive (a Drive file that must
   download first). Share the **same** attachment twice: it should not create a second entry in recents.
5. **Edit the original, reopen it:** the app shows the copy it made. Open or share the file again to refresh it. (This differs from Linux and Windows and is stated in the README.)
6. **Delete the original, then reopen from recents:** it still opens (it is the app's own copy). **Clear the app's storage in Settings** and the recents and copies are gone.
7. **Airplane mode / a captive portal** with the panel open: "Couldn't load results" and Retry, never a spinner that runs forever (20 s limit).
8. **A Google consent page or CAPTCHA** if one appears (EEA/UK, a VPN): it should be usable inside the panel; do not expect to sign in to Google there.
9. **Split screen, a foldable, a tablet:** the panel is a side panel at 600 dp and wider, a sheet below it. (Landscape on a phone was checked; the others were not.)
10. **Android 13+ real phone:** the predictive back animation (swipe back slowly with the panel open: the panel should shrink, then close). Checked only that the layering works on API 36.
11. **A phone with a missing, disabled or very old system WebView** (or disable "Android System WebView" in App info): the panel says search cannot run here and offers *Open in browser*; reading still works. (Code path only; this phone cannot test it.)
12. **Memory:** open a large PDF, search once, close the panel, keep reading for a while; watch whether the app is killed in the background more than you would like.

## Smoke test (5 minutes, worth repeating on every build)

* Open a PDF, long-press a word, drag a handle, tap **Find meaning**: results load; tap Back inside the panel; **Close**: the page is exactly where it was.
* Back button/gesture: closes the menu, the panel (its own history first), the contents, the selection, full screen, then leaves.
* Rotate the phone with the panel open: it becomes a side panel and back, on the same results.
* Kill the app from recents after a search, reopen it: the document is back at the same page and zoom, and the **search data from the earlier run is gone**.

Report anything that fails with the Android version, the phone model and the system WebView version (Settings -> Apps -> Android System WebView).
