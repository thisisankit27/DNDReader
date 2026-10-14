import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One quiet row: document title, page n / N (editable), rotate, zoom,
/// full screen, Open. No other chrome.
///
/// Controls that depend on a document are disabled while [pageCount] is null.
/// [onOpen] being null disables Open (used until a document can be opened).
class ReaderHeader extends StatelessWidget {
  const ReaderHeader({
    super.key,
    required this.title,
    this.pageNumber,
    this.pageCount,
    this.onGoToPage,
    this.onPageEditDone,
    this.onOpen,
    this.onZoomIn,
    this.onZoomOut,
    this.onRotate,
    this.fullscreen = false,
    this.onToggleFullscreen,
    this.onToggleContents,
    this.contentsOpen = false,
    this.menu,
  });

  final String title;

  /// Current page (1-based) and page count; null when no document is open.
  final int? pageNumber;
  final int? pageCount;

  /// Called with a valid page number when the reader types one and confirms.
  final ValueChanged<int>? onGoToPage;

  /// Called when editing the page number ends, so the owner can take focus back.
  final VoidCallback? onPageEditDone;
  final VoidCallback? onOpen;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  /// Rotates the document a quarter turn clockwise.
  final VoidCallback? onRotate;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  /// Shows or hides the table of contents; null disables the button.
  final VoidCallback? onToggleContents;
  final bool contentsOpen;

  /// Trailing overflow menu.
  final Widget? menu;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDocument = pageCount != null;

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
              return IconButtonTheme(
                // Narrow windows: tighter buttons rather than dropping any.
                data: compact
                    ? IconButtonThemeData(
                        style: IconButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                    : const IconButtonThemeData(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Contents (Ctrl+T)',
                        isSelected: contentsOpen,
                        icon: const Icon(Icons.toc),
                        onPressed: hasDocument ? onToggleContents : null,
                      ),
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
                        PageField(
                          pageNumber: pageNumber,
                          pageCount: pageCount!,
                          onGoToPage: onGoToPage,
                          onDone: onPageEditDone,
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
                      IconButton(
                        tooltip: 'Rotate clockwise (Ctrl+R)',
                        icon: const Icon(Icons.rotate_right),
                        onPressed: hasDocument ? onRotate : null,
                      ),
                      IconButton(
                        tooltip: fullscreen
                            ? 'Exit full screen (F11)'
                            : 'Full screen (F11)',
                        icon: Icon(
                          fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        ),
                        onPressed: onToggleFullscreen,
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
                      if (menu != null) ...[const SizedBox(width: 2), menu!],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The page indicator: a small field showing the current page, followed by
/// "/ N". Type a number and press Enter to jump there; Esc or leaving the
/// field puts the current page back.
class PageField extends StatefulWidget {
  const PageField({
    super.key,
    required this.pageNumber,
    required this.pageCount,
    this.onGoToPage,
    this.onDone,
  });

  final int? pageNumber;
  final int pageCount;
  final ValueChanged<int>? onGoToPage;
  final VoidCallback? onDone;

  @override
  State<PageField> createState() => _PageFieldState();
}

class _PageFieldState extends State<PageField> {
  late final TextEditingController _text = TextEditingController(text: _shown);
  late final FocusNode _focus = FocusNode(debugLabel: 'page-number')
    ..addListener(_onFocusChange);

  String get _shown => '${widget.pageNumber ?? 1}';

  @override
  void didUpdateWidget(PageField old) {
    super.didUpdateWidget(old);
    // Follow scrolling, but never overwrite what is being typed.
    if (!_focus.hasFocus && _text.text != _shown) _text.text = _shown;
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    } else {
      _text.text = _shown; // abandoned edit: show the real page again
    }
  }

  void _submit(String value) {
    final n = int.tryParse(value.trim());
    if (n != null) {
      widget.onGoToPage?.call(n.clamp(1, widget.pageCount));
    }
    _finish();
  }

  void _finish() {
    _focus.unfocus();
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge;
    return Semantics(
      label: 'Page number, of ${widget.pageCount}',
      textField: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 34,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _text.text = _shown;
                  _finish();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const ValueKey('page-field'),
                controller: _text,
                focusNode: _focus,
                textAlign: TextAlign.center,
                style: style,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: _submit,
                onTapOutside: (_) {
                  if (_focus.hasFocus) _finish();
                },
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('/ ${widget.pageCount}', style: style),
        ],
      ),
    );
  }
}
