import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../build_info.dart';

/// The About dialog's lines describing the embedded browser.
///
/// Platform-specific because the engine is: Linux ships CEF (and the Chromium
/// build it bundles is this project's to keep patched); Windows uses Microsoft's
/// WebView2 Runtime, whose version is whatever is installed and which Microsoft
/// updates.
@visibleForTesting
String embeddedBrowserLines({required bool windows, String? runtimeVersion}) {
  if (!windows) return 'Embedded browser: $kBundledChromium';
  final runtime = (runtimeVersion == null || runtimeVersion.isEmpty)
      ? 'Microsoft Edge WebView2 Runtime (not found)'
      : 'Microsoft Edge WebView2 Runtime $runtimeVersion';
  return 'Embedded browser: $runtime\n'
      'Search data is kept in a temporary folder that is deleted when you quit.';
}

/// Resolves the lines for this platform; asks the Runtime for its version on
/// Windows.
Future<String> embeddedBrowserDescription() async {
  if (!Platform.isWindows) return embeddedBrowserLines(windows: false);
  String? version;
  try {
    version = await WebviewController.getWebViewVersion();
  } on PlatformException {
    version = null;
  }
  return embeddedBrowserLines(windows: true, runtimeVersion: version);
}
