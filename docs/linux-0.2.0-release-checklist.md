# DNDReader 0.2.0 — Linux owner checklist (needs a real install)

Package: `dist/dndreader_0.2.0-1_amd64.deb` — 341,599,198 bytes (≈ 326 MiB), sha256
`5cb7ca4059ff2538788e6561ec1a9582f73e4a1b2db9fb94ef4b66e49aee4b05`, built from `feat/windows-port` + the
`release/0.2.0-rc` commit. `dist/` is git-ignored: the file exists on this machine only.

Only what could **not** be verified without root and an installed package. Everything else is in
`docs/windows-verification/REPORT.md` §10.

1. **Install.** `sudo apt install ./dist/dndreader_0.2.0-1_amd64.deb`. Expect no dependency errors (the
   `Depends:` list is identical to 0.1.5's). Watch the output for `dndreader: could not load
   /etc/apparmor.d/dndreader` — that line means step 3 will fail.
2. **Launch from the app menu**, and once by `dndreader ~/…/some.pdf` from a terminal. Menu → About must say
   version **0.2.0** and `CEF 149.0.4 (Chromium 149.0.7827.156)`.
3. **The sandbox is actually active** (the one thing nobody has seen on an installed 0.2.0). Open a PDF, select
   a word, press `Ctrl+E`, wait for results, then in a terminal: `packaging/linux/verify-sandbox.sh`.
   Expect `AppArmor label: dndreader (unconfined)`, ≥ 1 renderer, each `Seccomp: 2` and in its own
   user/pid/net namespace, and `PASS`. If the panel instead says "Search can't run inside DNDReader here",
   the profile did not load: `sudo apparmor_parser -r -T -W /etc/apparmor.d/dndreader` and retry.
4. **Search through the installed app**: results load; click a result; Back (arrow enabled/disabled matches
   what is shown); Open in browser opens your default browser; close the panel and the page is where you left it.
5. **Failure on a real disconnect**: turn Wi-Fi off, press `Ctrl+E` on a selection → "Couldn't load results"
   appears within ~1–2 s and stays. Turn Wi-Fi on, press Retry → results load. (This has been verified in a
   network namespace with no interface, not with your actual network manager.)
6. **Clean quit**: close the window with the X. It should be gone in well under a second;
   `pgrep -x dndreader` prints nothing. Then
   `grep -rla -- "q=<the word you searched>" ~/.config/cef_user_data` should print nothing, and
   `Cookies`/`History` under `~/.config/cef_user_data/Default` should not have changed
   (`ls -l --time-style=full-iso`).
7. **Fail-closed without the profile (optional)**: `sudo apparmor_parser -R /etc/apparmor.d/dndreader`, launch
   DNDReader from the app menu, press `Ctrl+E` on a selection → the panel must say search can't run (not
   load results); then `sudo apparmor_parser -r -T -W /etc/apparmor.d/dndreader` to restore it. (Already
   verified from an unconfined launch of the build tree, not of the installed package.)
8. **Upgrade**: if 0.1.5 is installed, install 0.2.0 over it; settings (recent files, theme, zoom) should
   survive, and `/etc/apparmor.d/dndreader` is a conffile — answer `N` (keep) if dpkg asks.

Not covered by anyone: Wayland-native input (everything here used Flutter-level or X11 events), a second
Ubuntu release, and CEF 149.0.7827.156's age — check the CEF stable branch before distributing (plan §10).
