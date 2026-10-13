import 'package:flutter/material.dart';

/// One quiet row: document title, page n / N, zoom, Open. No other chrome.
///
/// Controls that depend on a document are disabled while [pageLabel] is null.
/// [onOpen] being null disables Open (used until a document can be opened).
class ReaderHeader extends StatelessWidget {
  const ReaderHeader({
    super.key,
    required this.title,
    this.pageLabel,
    this.onOpen,
    this.onZoomIn,
    this.onZoomOut,
  });

  final String title;

  /// e.g. `3 / 240`; null when no document is open.
  final String? pageLabel;
  final VoidCallback? onOpen;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDocument = pageLabel != null;

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (hasDocument) ...[
                      const SizedBox(width: 12),
                      Semantics(
                        label: 'Page $pageLabel',
                        excludeSemantics: true,
                        child: Text(
                          pageLabel!,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Zoom out',
                      icon: const Icon(Icons.remove),
                      onPressed: hasDocument ? onZoomOut : null,
                    ),
                    IconButton(
                      tooltip: 'Zoom in',
                      icon: const Icon(Icons.add),
                      onPressed: hasDocument ? onZoomIn : null,
                    ),
                    const SizedBox(width: 4),
                    if (compact)
                      IconButton.filledTonal(
                        tooltip: 'Open PDF (Ctrl+O)',
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: onOpen,
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Open'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
