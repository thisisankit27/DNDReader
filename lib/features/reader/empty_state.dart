import 'package:flutter/material.dart';

/// Shown when no document is open.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.onOpen,
    this.recents = const [],
    this.onOpenRecent,
  });

  /// Null disables the button (opening documents is not available yet).
  final VoidCallback? onOpen;

  /// Recently opened documents (already filtered to those that exist).
  final List<String> recents;
  final ValueChanged<String>? onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 56,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Open a PDF to start reading',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Select a word or passage, then choose Find meaning to look it up '
                'beside the page — without losing your place.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open PDF'),
              ),
              const SizedBox(height: 12),
              Text(
                'Ctrl+O',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Recent', style: theme.textTheme.labelLarge),
                ),
                const SizedBox(height: 4),
                for (final path in recents.take(5))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenRecent == null
                          ? null
                          : () => onOpenRecent!(path),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text(
                        path.split('/').last,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
