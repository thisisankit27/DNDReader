import 'package:dndreader/features/reader/pdf_view.dart';
import 'package:dndreader/features/search/embedded_browser_info.dart';
import 'package:dndreader/services/path_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('baseName', () {
    test('Windows splits on both separators', () {
      String n(String p) => baseName(p, windows: true);
      expect(
        n(r'C:\Users\a\Documents\Monster Manual.pdf'),
        'Monster Manual.pdf',
      );
      expect(
        n('C:/Users/a/Documents/Monster Manual.pdf'),
        'Monster Manual.pdf',
      );
      expect(n(r'C:\Users/a\Docs/x.pdf'), 'x.pdf');
      expect(n(r'\\server\share\book.pdf'), 'book.pdf');
      expect(n('book.pdf'), 'book.pdf');
      expect(n(r'C:\docs\'), 'docs');
    });

    test('elsewhere only / separates; a backslash is part of the name', () {
      String n(String p) => baseName(p, windows: false);
      expect(n('/home/a/Docs/book.pdf'), 'book.pdf');
      expect(n(r'/home/a/we\ird.pdf'), r'we\ird.pdf');
      expect(n('/home/a/'), 'a');
    });

    test('never returns an empty name', () {
      expect(baseName('', windows: true), '');
      expect(baseName('/', windows: false), '/');
      expect(baseName(r'\', windows: true), r'\');
    });
  });

  group('embeddedBrowserLines', () {
    test('Linux names the bundled CEF/Chromium build', () {
      final text = embeddedBrowserLines(windows: false);
      expect(text, contains('CEF'));
      expect(text, isNot(contains('WebView2')));
    });

    test('Windows shows the Runtime version and where search data lives', () {
      final text = embeddedBrowserLines(
        windows: true,
        runtimeVersion: '149.0.3800.58',
      );
      expect(text, contains('WebView2 Runtime 149.0.3800.58'));
      expect(text, contains('temporary folder'));
      expect(text, isNot(contains('CEF')));
    });

    test('Windows says so when the Runtime is not found', () {
      for (final v in <String?>[null, '']) {
        expect(
          embeddedBrowserLines(windows: true, runtimeVersion: v),
          contains('not found'),
        );
      }
    });
  });

  test('wheel factor is tuned per platform', () {
    // Windows reports ~100 px per notch, Linux ~53; both aim at ~100 px.
    expect(PdfView.wheelScrollFactorFor(windows: true) * 100, closeTo(100, 1));
    expect(PdfView.wheelScrollFactorFor(windows: false) * 53, closeTo(106, 1));
  });
}
