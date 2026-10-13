import 'package:dndreader/services/search_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeQuery', () {
    test('single word is unchanged', () {
      expect(normalizeQuery('fibrosis'), 'fibrosis');
    });

    test('trims and collapses runs of whitespace, tabs and newlines', () {
      expect(
        normalizeQuery('  idiopathic \t pulmonary\r\n  fibrosis  '),
        'idiopathic pulmonary fibrosis',
      );
    });

    test('multi-line selection becomes one line', () {
      expect(
        normalizeQuery('The quick brown\nfox jumps\nover the lazy dog.'),
        'The quick brown fox jumps over the lazy dog.',
      );
    });

    test('repairs a hyphenated line wrap', () {
      expect(normalizeQuery('idio-\npathic pulmonary'), 'idiopathic pulmonary');
      expect(normalizeQuery('idio-  \r\n   pathic'), 'idiopathic');
    });

    test(
      'keeps a real compound hyphen followed by a space on the same line',
      () {
        expect(
          normalizeQuery('pre- and post-operative care'),
          'pre- and post-operative care',
        );
      },
    );

    test(
      'keeps a hyphen before a capitalised continuation across a line break',
      () {
        expect(normalizeQuery('Smith-\nJones'), 'Smith- Jones');
      },
    );

    test('keeps hyphens inside words', () {
      expect(normalizeQuery('state-of-the-art'), 'state-of-the-art');
    });

    test('repairs wraps for non-ASCII letters', () {
      expect(normalizeQuery('über-\nsetzung'), 'übersetzung');
    });

    test('empty and whitespace-only selections are rejected', () {
      expect(normalizeQuery(''), isNull);
      expect(normalizeQuery('   \n\t  '), isNull);
    });

    test('caps long selections on a word boundary', () {
      final long = List.filled(2000, 'word').join(' ');
      final out = normalizeQuery(long)!;
      expect(out.length, lessThanOrEqualTo(kMaxQueryLength));
      expect(out.endsWith(' '), isFalse);
      expect(
        out.split(' ').every((w) => w == 'word'),
        isTrue,
        reason: 'no word was cut in half',
      );
    });

    test('a 5,000-character selection is capped, not rejected', () {
      expect(normalizeQuery('a' * 5000)!.length, kMaxQueryLength);
    });

    test('capping never splits a surrogate pair', () {
      final out = normalizeQuery('😀' * 400)!;
      expect(out.runes.length, kMaxQueryLength);
      expect(out.runes.every((r) => r == 0x1F600), isTrue);
    });
  });

  group('searchUriFor', () {
    test('builds the URL from the single template constant', () {
      expect(
        searchUriFor('idiopathic pulmonary fibrosis').toString(),
        '${kSearchUrlPrefix}idiopathic+pulmonary+fibrosis',
      );
    });

    test('percent-encodes reserved characters', () {
      final uri = searchUriFor('a&b=c+d #e ?f')!;
      expect(uri.queryParameters['q'], 'a&b=c+d #e ?f');
      expect(uri.toString(), isNot(contains('#')));
      expect(uri.fragment, isEmpty);
    });

    test('encodes quotes and em-dashes', () {
      final uri = searchUriFor('"cogito ergo sum" — Descartes')!;
      expect(uri.queryParameters['q'], '"cogito ergo sum" — Descartes');
    });

    test('encodes non-Latin text', () {
      final uri = searchUriFor('肺纤维化 Ελληνικά العربية')!;
      expect(uri.queryParameters['q'], '肺纤维化 Ελληνικά العربية');
      expect(uri.toString(), startsWith(kSearchUrlPrefix));
    });

    test('returns null when there is nothing to search', () {
      expect(searchUriFor('  \n '), isNull);
    });

    test('host and path are fixed regardless of input', () {
      final uri = searchUriFor('https://evil.example/?x=1')!;
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/search');
    });
  });
}
