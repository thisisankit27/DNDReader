import 'package:flutter/services.dart';

/// The installed system WebView's package and version (e.g. `com.google.android.webview 149.0.7827.160`),
/// asked of the Android framework (`WebView.getCurrentWebViewPackage`). Null where there is no such
/// channel (not Android, tests) or no WebView provider is installed.
Future<String?> systemWebViewVersion() async {
  try {
    return await const MethodChannel('dndreader/webview')
        .invokeMethod<String>('version');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
