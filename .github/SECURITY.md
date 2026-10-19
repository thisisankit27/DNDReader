# Security policy

DNDReader is a solo, open-source project. This page says what to report, how, and what to expect.

## Reporting a vulnerability

**Please report privately, not in a public issue.** Use GitHub's private reporting form:

<https://github.com/thisisankit27/DNDReader/security/advisories/new>

Only the maintainer can see it. Please include:

- the platform (Ubuntu, Windows or Android) and the DNDReader version (Menu, then About);
- what you did, what happened, and what you expected;
- whether it needs a particular PDF. If so, describe it rather than attaching a document you would not want public.

This is a one-person project, so there is no fixed response time and no bug bounty. Reports are read and answered as soon as possible, and you will be told what was decided. If you would like credit in the fix, say so.

## What is supported

Only the **latest published release** receives fixes. Older versions are not patched; update instead. The current release and its published checksums are on the [download page](https://dnd-reader.vibethroughcode.com/download/).

## In scope

- the application on Ubuntu, Windows and Android;
- the installer packages and release files (`.deb`, `.exe`, `.apk`), including their signing and checksums;
- how the search panel's browser is configured, sandboxed or isolated, and the AppArmor profile the Ubuntu package installs;
- the website in `site/`.

## Out of scope, and where to report instead

- **What Google shows in the search panel**, including AI Overviews, consent screens and CAPTCHAs. DNDReader loads Google Search; it does not control it.
- **Vulnerabilities in the browser engines themselves.** Windows uses Microsoft's WebView2 and Android uses the phone's system WebView; both are updated by their vendors, so report those to Microsoft or Google. The Ubuntu package bundles Chromium (through CEF), which is *this project's* job to keep updated: if a bundled-Chromium fix has not reached a release, that is in scope and worth reporting.
- Findings that need a rooted device, a compromised machine, or physical access.

## Checking that a download is genuine

Every download page shows the SHA-256 of each file. Android files are also signed with the project's release key, whose certificate fingerprint is published on the [Android page](https://dnd-reader.vibethroughcode.com/download/android/). **If a checksum or signature does not match, do not run the file** and report it using the form above.
