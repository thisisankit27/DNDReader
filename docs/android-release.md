# Android: signing and building a release

A signed release APK is reproducible from this repository plus a keystore that lives **outside** it. Nothing secret
is ever committed: `android/key.properties`, `*.jks` and `*.keystore` are gitignored (`android/.gitignore`), the
release workflow writes them from CI secrets, and `android/app/build.gradle.kts` reads them at build time.

## Identity (owner decisions, 2026-10-19)

| | |
|---|---|
| Application id | `io.github.thisisankit27.dndreader` (permanent once published) |
| minSdk / targetSdk | 26 / 36 |
| Display name | `DNDReader` |
| Distribution | Signed APK on GitHub Releases first. Google Play is not set up (see "Play" below) |
| Permission | `INTERNET` only |

## Version code

`versionCode` is derived from the `version:` in `pubspec.yaml` (`0.2.2+1`) so it only ever rises with the version:

```
major*1_000_000 + minor*10_000 + patch*100 + build        0.2.2+1  ->  20201
```

Flutter adds `1000 x ABI` for split APKs: armeabi-v7a 1, arm64-v8a 2, x86_64 4 (so `0.2.2+1` is 21201, 22201 and 24201).
The build fails if a part does not fit (patch and build must be 99 or less). Raise the version in `pubspec.yaml` for every
release; never reuse a code that has been distributed.

## One-time: create the keystore (keep it, and its passwords, somewhere safe; losing it means you can never update the app)

```bash
keytool -genkeypair -v -keystore ~/dndreader-release.jks -alias dndreader \
  -keyalg RSA -keysize 4096 -validity 10000
```

Back it up in at least two places. **Do not** put it in the repository, in a chat, or in an issue.

## Build and sign locally

```bash
cat > android/key.properties <<EOF2
storeFile=/home/you/dndreader-release.jks
storePassword=...
keyAlias=dndreader
keyPassword=...
EOF2

DNDREADER_REQUIRE_RELEASE_SIGNING=1 \
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```

`DNDREADER_REQUIRE_RELEASE_SIGNING=1` makes a missing `key.properties` a hard error; without it Gradle signs with the
**debug** key and prints a warning (good for trying the app, not for distributing).

Check what you built:

```bash
APK=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
.github/scripts/android-check-apk.sh "$APK" 25000000     # size, libraries, 16 KB alignment, permissions
$ANDROID_HOME/build-tools/36.0.0/apksigner verify --print-certs "$APK"
sha256sum build/app/outputs/flutter-apk/app-*-release.apk
```

Keep `build/symbols` (the `--split-debug-info` output) for every release you distribute: it is what turns an obfuscated
crash stack back into names.

## Build in CI instead

`.github/workflows/android-release.yml` does the same on `ubuntu-latest` from four repository secrets
(`ANDROID_KEYSTORE_BASE64` = `base64 -w0 ~/dndreader-release.jks`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`). Run it from the Actions tab, or push a tag `android-v0.2.2`. It uploads the APKs and `SHA256SUMS` as
a workflow artifact and **publishes nothing**; download the artifact and attach it to a GitHub Release yourself. Without
the secrets it stops at its first step.

## What the gates enforce (and why they are in the build)

* arm64 APK within **25,000,000 bytes** (the budget; measured 24.85 MB, about 150 KB of headroom: a new dependency or asset will trip it).
* Native libraries are exactly `libapp`, `libdartjni`, `libdatastore_shared_counter`, `libflutter`, `libpdfium`. Anything with
  cef/webview2/chromium in its name fails, because the system WebView is already on the phone.
* Every library is 16 KB-page safe (LOAD alignment >= 0x4000, stored libraries 16 KB zip-aligned). A Play requirement for
  apps targeting Android 15+ on 16 KB devices.
* Permissions: `INTERNET` and AndroidX's own `<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (signature-level, for the
  app's own broadcast receivers) and nothing else. A new permission is an owner decision.

## Play (not set up; what it would take)

Not done and not needed for GitHub Releases. As recalled, **not verified against current Play documentation**: a developer account; a
privacy-policy URL; a data-safety declaration (the app sends the selected text to Google and stores nothing remotely); a content
rating; a target-API floor (the app targets 36); an app bundle instead of APKs (`flutter build appbundle`); and, for new
*personal* accounts, a closed-testing period with a minimum number of testers (order of 12 testers for 14 days) before production access.
Distributing through Google's own store also sharpens the open question in `docs/implementation-plan.md` section 9.8 (whether Google's terms
permit Search inside a third-party app panel). That is the owner's call, with legal advice if it matters; nothing here decides it.
