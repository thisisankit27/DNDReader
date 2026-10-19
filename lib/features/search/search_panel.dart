import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'search_session.dart';
import 'search_web_view.dart';

/// The docked search panel: a header (query, Back, Open in browser, Close) over
/// the embedded browser, with calm states for loading, failure and "the sandbox
/// cannot start here".
class SearchPanel extends StatelessWidget {
  const SearchPanel({
    super.key,
    required this.session,
    required this.onClose,
    this.touch = false,
  });

  final SearchSession session;
  final VoidCallback onClose;

  /// Touch layout: no keyboard-shortcut text in labels (a screen reader reads them aloud).
  final bool touch;

  /// The explanation under "Search can't run inside DNDReader here".
  ///
  /// Platform-specific because the reason differs: the Linux browser sandbox
  /// versus the Windows WebView2 Runtime (plan W2).
  @visibleForTesting
  static String unavailableBody({
    required bool windows,
    bool android = false,
  }) => android
      ? 'The Android System WebView that shows search results is missing, disabled or '
            'can’t start on this device, so results are not loaded in the panel. You can '
            'open them in your browser instead.'
      : windows
      ? 'The Microsoft Edge WebView2 Runtime that shows search results isn’t available '
            'on this system, so results are not loaded in the panel. You can open them in '
            'your browser instead.'
      : 'The browser’s security sandbox couldn’t be started on this system, so results '
            'are not loaded in the panel. You can open them in your browser instead.';

  /// The note shown when Google asks for a cookie choice.
  @visibleForTesting
  static String consentNote({required bool windows, bool android = false}) =>
      android
      ? 'Google is asking for a cookie choice. It applies until DNDReader is closed and '
            'reopened — search data is kept in the app’s private storage and cleared '
            'the next time the app starts.'
      : windows
      ? 'Google is asking for a cookie choice. It applies until you quit DNDReader — '
            'search data is kept in a temporary folder that is deleted when you quit.'
      : 'Google is asking for a cookie choice. It applies until you quit DNDReader — '
            'search cookies are not kept on disk.';

  /// Panel width for a window of [windowWidth]: 420–480 px on desktop, never
  /// wider than the window.
  static double widthFor(double windowWidth) {
    return (windowWidth * 0.4).clamp(420.0, 480.0).clamp(0.0, windowWidth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return Material(
          color: theme.colorScheme.surface,
          elevation: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                _Header(session: session, onClose: onClose, touch: touch),
                if (unsandboxedDevOverrideActive) const _UnsandboxedBanner(),
                if (session.consentHint) const _ConsentHint(),
                Expanded(child: _Body(session: session)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.onClose,
    this.touch = false,
  });

  final SearchSession session;
  final VoidCallback onClose;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading =
        session.phase == SearchPhase.starting ||
        session.phase == SearchPhase.loading;
    return SizedBox(
      height: 56,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: session.canGoBack ? session.back : null,
                  ),
                  Expanded(
                    child: Tooltip(
                      message: session.queryText,
                      child: Semantics(
                        header: true,
                        label: 'Search results for ${session.queryText}',
                        child: Text(
                          session.queryText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open in browser',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: session.openInBrowser,
                  ),
                  IconButton(
                    tooltip: touch ? 'Close' : 'Close (Esc)',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 2,
            child: loading
                ? const LinearProgressIndicator()
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.session});

  final SearchSession session;

  @override
  Widget build(BuildContext context) {
    switch (session.phase) {
      case SearchPhase.unavailable:
        return _Message(
          icon: Icons.shield_outlined,
          title: 'Search can’t run inside DNDReader here',
          body: SearchPanel.unavailableBody(
            windows: Platform.isWindows,
            android: Platform.isAndroid,
          ),
          detail: session.unavailableReason,
          actionLabel: 'Open in browser',
          onAction: session.openInBrowser,
        );
      case SearchPhase.failed:
        return _Message(
          icon: Icons.wifi_off_outlined,
          title: 'Couldn’t load results',
          body: 'Check your connection and try again, or open the search in your browser.',
          actionLabel: 'Retry',
          onAction: session.retry,
          secondaryLabel: 'Open in browser',
          onSecondary: session.openInBrowser,
        );
      case SearchPhase.idle:
        return const SizedBox.shrink();
      case SearchPhase.starting:
      case SearchPhase.loading:
      case SearchPhase.loaded:
        final view = session.webView;
        return Stack(
          children: [
            Positioned.fill(child: view?.widget ?? const SizedBox.shrink()),
            if (session.phase == SearchPhase.starting)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.detail,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? detail;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 44, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsentHint extends StatelessWidget {
  const _ConsentHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        SearchPanel.consentNote(
          windows: Platform.isWindows,
          android: Platform.isAndroid,
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _UnsandboxedBanner extends StatelessWidget {
  const _UnsandboxedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        'DEVELOPMENT BUILD: the browser sandbox is OFF. Never ship this configuration.',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
