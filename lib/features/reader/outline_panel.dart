import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Table of contents: the document's own outline (bookmarks), as a tree.
///
/// Shown as a left-edge overlay so the document never reflows. [outline] is
/// null while it is still loading, and empty when the document has none.
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({
    super.key,
    required this.outline,
    required this.currentPage,
    required this.onSelect,
    required this.onClose,
  });

  /// Preferred width; clamped by the available space.
  static const double width = 300;

  final List<PdfOutlineNode>? outline;
  final int? currentPage;
  final ValueChanged<PdfDest> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = outline;

    final Widget body;
    if (nodes == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (nodes.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This document has no table of contents.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      body = ListView(
        key: const ValueKey('outline-list'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final node in nodes)
            _OutlineEntry(
              node: node,
              depth: 0,
              currentPage: currentPage,
              onSelect: onSelect,
            ),
        ],
      );
    }

    return Semantics(
      label: 'Table of contents',
      container: true,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Contents',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close contents (Esc)',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineEntry extends StatelessWidget {
  const _OutlineEntry({
    required this.node,
    required this.depth,
    required this.currentPage,
    required this.onSelect,
  });

  final PdfOutlineNode node;
  final int depth;
  final int? currentPage;
  final ValueChanged<PdfDest> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dest = node.dest;
    final isCurrent = dest != null && dest.pageNumber == currentPage;
    final title = node.title.trim().isEmpty ? '(untitled)' : node.title.trim();

    final row = InkWell(
      onTap: dest == null ? null : () => onSelect(dest),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 + depth * 16.0, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w600 : null,
                  color: dest == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            if (dest != null) ...[
              const SizedBox(width: 8),
              Text(
                '${dest.pageNumber}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (node.children.isEmpty) return row;

    // Parents are expanded by default: a short outline reads as one list.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        for (final child in node.children)
          _OutlineEntry(
            node: child,
            depth: depth + 1,
            currentPage: currentPage,
            onSelect: onSelect,
          ),
      ],
    );
  }
}
