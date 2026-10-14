import 'package:dndreader/features/search/search_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('platform-specific panel text', () {
    test('Windows names the WebView2 Runtime, not the Linux sandbox', () {
      final text = SearchPanel.unavailableBody(windows: true);
      expect(text, contains('WebView2 Runtime'));
      expect(text, isNot(contains('sandbox')));
      expect(text, contains('open them in your browser'));
    });

    test('Linux keeps the sandbox wording', () {
      final text = SearchPanel.unavailableBody(windows: false);
      expect(text, contains('security sandbox'));
      expect(text, isNot(contains('WebView2')));
    });

    test('Windows does not claim cookies are never written to disk', () {
      final text = SearchPanel.consentNote(windows: true);
      expect(text, isNot(contains('not kept on disk')));
      expect(text, contains('temporary folder'));
      expect(text, contains('deleted when you quit'));
    });

    test('Linux keeps its in-memory claim', () {
      expect(
        SearchPanel.consentNote(windows: false),
        contains('not kept on disk'),
      );
    });
  });
}
