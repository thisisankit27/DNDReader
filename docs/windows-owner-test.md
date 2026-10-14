# Windows: what to install and what to test

## Install (nothing else is needed)

Windows 10 **1809 or later**, 64-bit (or Windows 11). You do **not** need Flutter, Visual Studio or Inno Setup —
CI builds the installer.

1. Get the installer from the latest green **windows** workflow run on `main`: GitHub → *Actions* → *windows* →
   the newest run → artifact **`dndreader-windows-installer`** (needs a GitHub login). Or:
   `gh run list --workflow windows --branch main --limit 1` then
   `gh run download <run-id> -n dndreader-windows-installer`. (Artifacts are kept for 90 days.)
2. Unzip, run **`DNDReader-0.2.0-setup-x64.exe`**. It is **unsigned**, so Windows shows *"Windows protected your
   PC"* or *"Unknown publisher"* → *More info* → *Run anyway*. It installs per-user (no admin prompt) to
   `%LOCALAPPDATA%\Programs\DNDReader`.
3. The **Microsoft Edge WebView2 Runtime** is required for the search panel. It ships with Windows 11 and almost
   all Windows 10 machines; if it is missing the installer fetches it (bundled ~2 MB bootstrapper).

## Test — what is still unverified (everything else was verified on one Windows 10 22H2 machine)

Use only `test_fixtures/*.pdf` from the repo (or any PDF of your own that you are happy to open).

1. **Windows 11 only — capture border.** Open a PDF, select a word, `Ctrl+E`. Is there a **yellow border** around
   the search panel? (Expected: none; unconfirmed.)
2. **Runtime missing (a clean Windows 10 VM, if you have one).** Install; the wizard should install the Runtime and
   the panel should work. Without it the panel must say search can't run and offer *Open in browser*.
3. **Other display scales.** Delete `%APPDATA%\dndreader\window-size`, set Settings → Display → Scale to 100 %,
   125 %, 200 % in turn and launch: the **whole window must sit above the taskbar** each time.
4. **Explorer integration.** Right-click a `.pdf` → *Open with* → DNDReader: the file opens.
5. **Real network loss.** Turn Wi-Fi off, `Ctrl+E` → "Couldn't load results" within a couple of seconds and it
   *stays*; Wi-Fi on → *Retry* loads. (Verified only with a simulated outage.)
6. **Per-machine install** (optional): run the installer elevated / choose "all users".

## Smoke test (5 minutes, worth repeating on this build)

7. Open a PDF; select a word; **Find meaning** → results load; click a result; **Back**; *Open in browser*.
8. Close the panel (`Esc`): scroll position unchanged; `Ctrl+T`, `Ctrl+R`, arrow keys work immediately. Also after
   typing a page number + Enter.
9. `F11` in / `Esc` out; header icon toggles.
10. **Quit** with the X after a search: it closes in about a second and
    `%TEMP%\dndreader-search-*` is **gone**. Then use a search, kill it from Task Manager, relaunch **without
    searching**: the leftover folder disappears within a few seconds.
11. **Uninstall** (Settings → Apps): the install folder, `%APPDATA%\dndreader`, `%APPDATA%\com.dndreader` and
    any `%TEMP%\dndreader-search-*` are removed.

Report anything that fails with the Windows build number and display scale.
