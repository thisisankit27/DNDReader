import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'empty_state.dart';
import 'reader_header.dart';

/// The single screen: header on top, reading surface below.
///
/// M1 renders the shell and the empty state only; opening and rendering PDFs
/// arrives with the reader milestone. [onOpen] stays null until then, which
/// keeps the Open controls honestly disabled.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): ?onOpen,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              ReaderHeader(title: 'DNDReader', onOpen: onOpen),
              Expanded(child: EmptyState(onOpen: onOpen)),
            ],
          ),
        ),
      ),
    );
  }
}
