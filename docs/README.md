# Documentation index

| Document | What it is | Status |
|---|---|---|
| [`implementation-plan.md`](implementation-plan.md) | The Linux/product plan: decisions, risks, definition of done | Plan of record |
| [`windows-implementation-plan.md`](windows-implementation-plan.md) | The Windows port plan (WebView2) | Plan of record; implemented |
| [`progress.md`](progress.md) | Append-only log of what was *observed*, milestone by milestone | Living log |
| [`completion-report.md`](completion-report.md) | Ubuntu MVP (v0.1.5) delivery report | Historical |
| [`completion-report-windows.md`](completion-report-windows.md) | Windows port delivery report | Historical (see its update banner) |
| [`windows-verification/REPORT.md`](windows-verification/REPORT.md) | Defects D1–D7 from the real-machine run, how they were fixed and verified (§0), and the Linux regression/release-candidate passes (§9–10) | Current evidence |
| [`windows-owner-test.md`](windows-owner-test.md) | What to install and test on Windows | Current |
| [`android-owner-test.md`](android-owner-test.md) | What to install and test on Android, and what was and was not verified | Current |
| [`android-release.md`](android-release.md) | Signing, version codes and building a release APK; the CI gates | Current |
| [`search-web-view-contract.md`](search-web-view-contract.md) | The `SearchWebView` adapter contract: what a CEF/WebView2/future adapter must do | Current |
| [`linux-0.2.0-release-checklist.md`](linux-0.2.0-release-checklist.md) | Post-install checks for the `.deb` | Done (owner-confirmed) |
| [`linux-0.2.1-release-checklist.md`](linux-0.2.1-release-checklist.md) | Post-install checks for the 0.2.1 GNOME 50 crash fix | Needs the owner's install |
| [`linux-0.2.2-release-checklist.md`](linux-0.2.2-release-checklist.md) | Post-install checks for 0.2.2 (narrower workaround, AppArmor ABI fix) | Needs the owner's install |

Rule for new evidence: the repository is public — do not commit screenshots, machine names, user names or
personal paths; describe observations in text.
