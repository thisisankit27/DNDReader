import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../services/search_url.dart';

/// Decides whether the "Find meaning" action is available, and for what text.
///
/// pdfrx reports every selection change; this debounces them, reads the text
/// once the selection has settled, normalises it with [normalizeQuery], and
/// holds the result so the action never has to re-read a selection that may
/// have changed. A selection with no searchable text (empty / whitespace) is
/// the "no selection" state: no action, no navigation.
class SelectionActionController extends ChangeNotifier {
  SelectionActionController({
    this.debounce = const Duration(milliseconds: 120),
  });

  final Duration debounce;

  PdfTextSelection? _selection;
  String? _query;
  bool _dismissed = false;
  Timer? _timer;
  int _generation = 0;

  /// The live selection object (anchors are computed from it).
  PdfTextSelection? get selection => _selection;

  /// The normalised query, or null when there is nothing searchable.
  String? get query => _query;

  /// Whether the action should be shown.
  bool get available => _query != null && !_dismissed;

  /// pdfrx's `onTextSelectionChange`.
  void onSelectionChanged(PdfTextSelection selection) {
    _selection = selection;
    _dismissed = false;
    _timer?.cancel();
    final generation = ++_generation;
    if (!selection.hasSelectedText) {
      _setQuery(null);
      return;
    }
    _timer = Timer(debounce, () => _settle(selection, generation));
  }

  Future<void> _settle(PdfTextSelection selection, int generation) async {
    final raw = await selection.getSelectedText();
    if (generation != _generation) return; // a newer change superseded this one
    _setQuery(normalizeQuery(raw));
  }

  /// Hides the action until the selection changes again (Esc).
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  /// Forgets everything (a different document was opened).
  void reset() {
    _timer?.cancel();
    _generation++;
    _selection = null;
    _dismissed = false;
    _setQuery(null);
  }

  void _setQuery(String? value) {
    if (_query == value) {
      notifyListeners();
      return;
    }
    _query = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
