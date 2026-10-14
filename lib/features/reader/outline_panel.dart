import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Table of contents: the document's own outline (bookmarks), as a tree.
///
/// Shown as a left-edge overlay so the document never reflows. [outline] is
/// null while it is still loading, and empty when the document has none.
///
/// Topics with sub-topics start collapsed, except the branch that holds
/// [currentPage], so the reader sees where they are without scrolling a long
/// book's whole outline. The chevron toggles a topic; the title navigates.
class OutlinePanel extends StatefulWidget {
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
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final Set<PdfOutlineNode> _expanded = {};

  @override
  void initState() {
    super.initState();
    _expandCurrentBranch();
  }

  @override
  void didUpdateWidget(OutlinePanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.outline, widget.outline)) {
      _expanded.clear();
      _expandCurrentBranch();
    }
  }

  /// Opens the ancestors of the entry the reader is currently inside: the last
  /// entry, in document order, that starts on or before the current page.
  void _expandCurrentBranch() {
    final nodes = widget.outline;
    final page = widget.currentPage;
    if (nodes == null || page == null) return;

    List<PdfOutlineNode>? best;
    void walk(List<PdfOutlineNode> list, List<PdfOutlineNode> ancestors) {
      for (final node in list) {
        final dest = node.dest;
        if (dest != null && dest.pageNumber <= page) best = ancestors;
        walk(node.children, [...ancestors, node]);
      }
    }

    walk(nodes, const []);
    if (best != null) _expanded.addAll(best!);
  }

  void _toggle(PdfOutlineNode node) {
    setState(() {
      if (!_expanded.remove(node)) _expanded.add(node);
    });
  }

  /// The rows that are currently visible, in order.
  List<(PdfOutlineNode, int)> _visibleRows(List<PdfOutlineNode> nodes) {
    final rows = <(PdfOutlineNode, int)>[];
    void add(List<PdfOutlineNode> list, int depth) {
      for (final node in list) {
        rows.add((node, depth));
        if (_expanded.contains(node)) add(node.children, depth + 1);
      }
    }

    add(nodes, 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = widget.outline;

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
      final rows = _visibleRows(nodes);
      body = ListView.builder(
        key: const ValueKey('outline-list'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final (node, depth) = rows[i];
          return _OutlineEntry(
            node: node,
            depth: depth,
            expanded: _expanded.contains(node),
            currentPage: widget.currentPage,
            onSelect: widget.onSelect,
            onToggle: () => _toggle(node),
          );
        },
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
                        onPressed: widget.onClose,
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
    required this.expanded,
    required this.currentPage,
    required this.onSelect,
    required this.onToggle,
  });

  static const double _chevronSize = 28;

  final PdfOutlineNode node;
  final int depth;
  final bool expanded;
  final int? currentPage;
  final ValueChanged<PdfDest> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dest = node.dest;
    final isCurrent = dest != null && dest.pageNumber == currentPage;
    final title = node.title.trim().isEmpty ? '(untitled)' : node.title.trim();
    final hasChildren = node.children.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: 8 + depth * 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasChildren)
            SizedBox(
              width: _chevronSize,
              height: _chevronSize + 8,
              child: IconButton(
                key: ValueKey('outline-toggle-$title'),
                padding: EdgeInsets.zero,
                iconSize: 20,
                tooltip: expanded ? 'Collapse' : 'Expand',
                icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                onPressed: onToggle,
              ),
            )
          else
            const SizedBox(width: _chevronSize),
          Expanded(
            child: InkWell(
              onTap: dest == null ? null : () => onSelect(dest),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
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
            ),
          ),
        ],
      ),
    );
  }
}
