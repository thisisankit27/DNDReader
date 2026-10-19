import 'package:flutter/widgets.dart';

/// Lets the reader take the system back gesture/button while it has something to dismiss, and lets the
/// system do its own thing (leave the app, with the predictive-back animation on Android 13+) when it does not.
///
/// This is what `PopScope` does, held as a plain object so the reader's widget tree is not re-wrapped.
/// [setBusy] says whether there is anything to dismiss; [onBack] is called, instead of leaving, when there is.
class BackScope implements PopEntry<Object?> {
  BackScope({required this.onBack});

  final VoidCallback onBack;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);

  ModalRoute<dynamic>? _route;

  /// Re-registers with the route that currently contains [context]. Call from `didChangeDependencies`.
  void attach(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _route?.unregisterPopEntry(this);
    _route = route;
    _route?.registerPopEntry(this);
  }

  /// True while there is something for back to dismiss.
  void setBusy(bool busy) => canPopNotifier.value = !busy;

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) onBack();
  }

  void dispose() {
    _route?.unregisterPopEntry(this);
    _route = null;
    canPopNotifier.dispose();
  }
}
