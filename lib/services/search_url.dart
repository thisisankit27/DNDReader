/// Turns a PDF text selection into a search URL.
///
/// PDF selections are messy: hard line breaks, hyphenated line wraps, stray
/// whitespace. This is the only non-trivial pure logic in the app, so it is
/// kept free of Flutter imports and unit-tested.
library;

/// The single place the search engine is named. Changing the engine is a
/// product decision (plan §2), not an implementation detail.
const String kSearchUrlPrefix = 'https://www.google.com/search?q=';

/// Longest query we will send, on a word boundary where possible. A search
/// query, not a document.
const int kMaxQueryLength = 300;

// A hyphen at the *end of a line* followed by a lowercase continuation is a
// typesetting wrap ("idio-\npathic"). A hyphen followed by a space on the same
// line ("pre- and post-operative") is a real compound and must be kept, so the
// repair only applies across a line break.
final RegExp _wrappedHyphen = RegExp(
  r'(\p{L})-[ \t]*\r?\n[ \t]*(\p{Ll})',
  unicode: true,
);
final RegExp _whitespaceRun = RegExp(r'\s+', unicode: true);

/// Returns the cleaned query for [rawSelection], or `null` when nothing
/// searchable remains (empty or whitespace only).
String? normalizeQuery(String rawSelection, {int maxLength = kMaxQueryLength}) {
  var text = rawSelection;

  // 1. Repair line-wrap hyphenation while line breaks are still visible.
  text = text.replaceAllMapped(_wrappedHyphen, (m) => '${m[1]}${m[2]}');

  // 2. Collapse CR/LF/tabs and runs of whitespace, then trim.
  text = text.replaceAll(_whitespaceRun, ' ').trim();

  // 3. Nothing left: no navigation.
  if (text.isEmpty) return null;

  // 4. Cap length on a word boundary (code points, so no split surrogate pair).
  final runes = text.runes.toList();
  if (runes.length > maxLength) {
    var cut = maxLength;
    final space = runes.sublist(0, maxLength).lastIndexOf(0x20);
    if (space > 0) cut = space;
    text = String.fromCharCodes(runes.sublist(0, cut)).trimRight();
  }
  return text;
}

/// Builds the search [Uri] for [rawSelection], or `null` if it has no
/// searchable text. The text is percent-encoded into the single URL template.
Uri? searchUriFor(String rawSelection) {
  final query = normalizeQuery(rawSelection);
  if (query == null) return null;
  return Uri.parse('$kSearchUrlPrefix${Uri.encodeQueryComponent(query)}');
}
