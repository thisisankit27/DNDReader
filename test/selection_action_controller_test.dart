import 'dart:async';

import 'package:dndreader/features/reader/selection_action_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// A selection whose text can be set by the test. Only what the controller
/// touches is meaningful; the rest satisfies the interface.
class FakeSelection implements PdfTextSelection {
  FakeSelection(this.text);

  String text;
  int reads = 0;

  @override
  bool get hasSelectedText => text.isNotEmpty;

  @override
  Future<String> getSelectedText() async {
    reads++;
    return text;
  }

  @override
  bool get isTextSelectionEnabled => true;
  @override
  bool get isCopyAllowed => true;
  @override
  bool get isSelectingAllText => false;
  @override
  PdfTextSelectionRange? get textSelectionPointRange => null;
  @override
  Future<List<PdfPageTextRange>> getSelectedTextRanges() async => const [];
}

void main() {
  const settle = Duration(milliseconds: 20);
  Future<void> wait([Duration d = const Duration(milliseconds: 60)]) =>
      Future<void>.delayed(d);

  SelectionActionController make() =>
      SelectionActionController(debounce: settle);

  test(
    'becomes available with the normalised query after the debounce',
    () async {
      final c = make();
      addTearDown(c.dispose);
      c.onSelectionChanged(FakeSelection('  idio-\npathic   fibrosis '));
      expect(c.available, isFalse, reason: 'not before the selection settles');
      await wait();
      expect(c.available, isTrue);
      expect(c.query, 'idiopathic fibrosis');
    },
  );

  test(
    'resolveQueryNow reads the current selection before the debounce',
    () async {
      final c = make();
      addTearDown(c.dispose);
      c.onSelectionChanged(FakeSelection('  fast   word '));
      expect(c.available, isFalse, reason: 'pill not shown yet');
      expect(await c.resolveQueryNow(), 'fast word');
    },
  );

  test('resolveQueryNow is null with no searchable selection', () async {
    final c = make();
    addTearDown(c.dispose);
    expect(await c.resolveQueryNow(), isNull);
    c.onSelectionChanged(FakeSelection('   '));
    expect(await c.resolveQueryNow(), isNull);
  });

  test('a burst of changes is read once, for the last selection', () async {
    final c = make();
    addTearDown(c.dispose);
    final a = FakeSelection('first');
    final b = FakeSelection('second');
    c.onSelectionChanged(a);
    c.onSelectionChanged(b);
    await wait();
    expect(a.reads, 0);
    expect(b.reads, 1);
    expect(c.query, 'second');
  });

  test('a whitespace-only selection is the no-selection state', () async {
    final c = make();
    addTearDown(c.dispose);
    c.onSelectionChanged(FakeSelection('   \n\t '));
    await wait();
    expect(c.available, isFalse);
    expect(c.query, isNull);
  });

  test('an emptied selection hides the action immediately', () async {
    final c = make();
    addTearDown(c.dispose);
    final s = FakeSelection('word');
    c.onSelectionChanged(s);
    await wait();
    expect(c.available, isTrue);
    s.text = '';
    c.onSelectionChanged(s);
    expect(c.available, isFalse);
  });

  test('dismiss hides it until the selection changes again', () async {
    final c = make();
    addTearDown(c.dispose);
    final s = FakeSelection('word');
    c.onSelectionChanged(s);
    await wait();
    c.dismiss();
    expect(c.available, isFalse);
    s.text = 'another';
    c.onSelectionChanged(s);
    await wait();
    expect(c.available, isTrue);
    expect(c.query, 'another');
  });

  test('reset forgets the selection and cancels a pending read', () async {
    final c = make();
    addTearDown(c.dispose);
    final s = FakeSelection('word');
    c.onSelectionChanged(s);
    c.reset();
    await wait();
    expect(c.available, isFalse);
    expect(s.reads, 0);
    expect(c.selection, isNull);
  });

  test('a stale read cannot overwrite a newer selection', () async {
    final c = make();
    addTearDown(c.dispose);
    final slow = _SlowSelection('slow');
    c.onSelectionChanged(slow);
    await wait(
      const Duration(milliseconds: 30),
    ); // debounce fired, read pending
    c.onSelectionChanged(FakeSelection('fresh'));
    slow.complete();
    await wait(const Duration(milliseconds: 80));
    expect(c.query, 'fresh');
  });
}

class _SlowSelection extends FakeSelection {
  _SlowSelection(super.text);

  final _gate = Completer<String>();
  void complete() => _gate.complete(text);

  @override
  Future<String> getSelectedText() => _gate.future;
}
