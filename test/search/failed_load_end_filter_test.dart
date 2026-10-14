import 'package:dndreader/features/search/search_web_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FailedLoadEndFilter', () {
    test('forwards load-ends when nothing failed', () {
      final f = FailedLoadEndFilter();
      expect(f.shouldForwardEnd('https://a/'), isTrue);
      expect(f.shouldForwardEnd('about:blank'), isTrue);
    });

    test('drops the failed URL\'s trailing load-end, once', () {
      final f = FailedLoadEndFilter()..failed('https://a/');
      expect(f.shouldForwardEnd('about:blank'), isTrue, reason: 'other frame');
      expect(f.shouldForwardEnd('https://a/'), isFalse);
      expect(f.shouldForwardEnd('https://a/'), isTrue, reason: 'only once');
    });

    test('a new navigation clears the pairing (Retry of the same URL)', () {
      final f = FailedLoadEndFilter()..failed('https://a/');
      f.navigationStarted();
      expect(f.shouldForwardEnd('https://a/'), isTrue);
    });
  });
}
