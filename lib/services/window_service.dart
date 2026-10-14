import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Full-screen control for the window, over the runner's `dndreader/window`
/// channel (Linux). Flutter itself has no window API, and a plugin for one
/// would be a new dependency for a single call.
///
/// Where the channel does not exist (tests, other platforms) every call is a
/// harmless no-op and [fullscreen] stays false.
class WindowService extends ChangeNotifier {
  WindowService() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('dndreader/window');

  bool _fullscreen = false;

  bool get fullscreen => _fullscreen;

  Future<void> setFullscreen(bool value) async {
    try {
      await _channel.invokeMethod<void>('setFullscreen', value);
    } on MissingPluginException {
      // No native window layer here.
    } on PlatformException {
      // The window manager refused; the state stays as it was.
    }
  }

  Future<void> toggleFullscreen() => setFullscreen(!_fullscreen);

  /// The native side reports the real state, including changes the window
  /// manager makes on its own (e.g. a compositor shortcut).
  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'fullscreenChanged' && call.arguments is bool) {
      final value = call.arguments as bool;
      if (value != _fullscreen) {
        _fullscreen = value;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
