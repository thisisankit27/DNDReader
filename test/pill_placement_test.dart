import 'dart:ui';

import 'package:dndreader/features/reader/pill_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Size(1000, 700);
  const pill = Size(180, 44);

  PillPlacement place(Rect anchor, {Rect? avoid}) =>
      placePill(viewport: viewport, pill: pill, anchor: anchor, avoid: avoid);

  test('goes directly below the last character, centred on it', () {
    final p = place(const Rect.fromLTWH(400, 200, 10, 20));
    expect(p.above, isFalse);
    expect(p.offset.dy, 200 + 20 + 8); // anchor.bottom + gap
    expect(p.offset.dx + pill.width / 2, closeTo(405, 0.001));
    expect(p.overlapsAnchor, isFalse);
  });

  test('flips above the selection when there is no room below', () {
    const anchor = Rect.fromLTWH(400, 660, 10, 20);
    final p = place(anchor);
    expect(p.above, isTrue);
    expect(p.offset.dy + pill.height + 8, closeTo(anchor.top, 0.001));
    expect(p.overlapsAnchor, isFalse);
  });

  test(
    'a multi-line selection flips above the selection top, not the last line',
    () {
      const end = Rect.fromLTWH(400, 660, 10, 20);
      const bounds = Rect.fromLTWH(100, 560, 700, 120);
      final p = place(end, avoid: bounds);
      expect(p.above, isTrue);
      expect(p.offset.dy + pill.height + 8, closeTo(bounds.top, 0.001));
    },
  );

  test('is clamped inside the viewport at the left and right edges', () {
    final left = place(const Rect.fromLTWH(2, 100, 10, 20));
    expect(left.offset.dx, 8);
    final right = place(const Rect.fromLTWH(995, 100, 10, 20));
    expect(right.offset.dx + pill.width, 1000 - 8);
  });

  test(
    'never leaves the viewport vertically, even with no room on either side',
    () {
      // A selection taller than the viewport: nowhere clean to put the pill.
      const tall = Rect.fromLTWH(100, -200, 600, 1100);
      final p = place(const Rect.fromLTWH(400, 880, 10, 20), avoid: tall);
      expect(p.offset.dy, greaterThanOrEqualTo(8));
      expect(p.offset.dy + pill.height, lessThanOrEqualTo(700 - 8));
      expect(
        p.overlapsAnchor,
        isTrue,
        reason: 'the degenerate case is reported, not hidden',
      );
    },
  );

  test('a pill wider than the viewport does not produce a negative offset', () {
    final p = placePill(
      viewport: const Size(120, 300),
      pill: pill,
      anchor: const Rect.fromLTWH(50, 50, 10, 20),
    );
    expect(p.offset.dx, 8);
  });
}
