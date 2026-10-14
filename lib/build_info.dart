/// Facts shown in the About dialog. Update with each release / CEF bump.
///
/// `kBundledChromium` is the Chromium (CEF) build the pinned `webview_cef` fork
/// downloads — see `third/download.cmake` in the fork. Keeping it visible is part
/// of the CEF bump policy (plan §10): Chromium security updates are this
/// project's responsibility.
const String kAppVersion = '0.1.1';
const String kBundledChromium = 'CEF 149.0.4 (Chromium 149.0.7827.156)';
