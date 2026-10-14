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

// What PDFium/pdfrx actually hands us for line-wrapped words (observed in M2,
// gate 1; see docs/progress.md):
//   * a hyphen glyph at the end of a line followed by a lowercase continuation
//     arrives as U+2010 + "\n" ("silico‐\nvolcano"); the ASCII hyphen
//     variant arrives as U+0002 with the line break swallowed ("well\u0002known");
//   * invisible soft hyphens (U+00AD) may remain inside words;
//   * superscripts and table cells arrive as separate lines ("x\n2").
// A hyphen followed by a space on the *same* line ("pre- and post-operative")
// is a real compound and must be kept, so wrap repair only crosses a line break.
final RegExp _wrappedHyphen = RegExp(
  r'(\p{L})[-\u2010][ \t]*\r?\n[ \t]*(\p{Ll})',
  unicode: true,
);
final RegExp _controlChars = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]',
);
final RegExp _whitespaceRun = RegExp(r'\s+', unicode: true);

/// Returns the cleaned query for [rawSelection], or `null` when nothing
/// searchable remains (empty or whitespace only).
String? normalizeQuery(String rawSelection, {int maxLength = kMaxQueryLength}) {
  var text = rawSelection;

  // 1. Drop invisible soft hyphens and PDFium's U+0002 hyphen-at-line-end marker
  //    (the two halves of the word are joined), then repair visible wrap hyphens
  //    while line breaks are still visible.
  text = text.replaceAll('\u00AD', '').replaceAll('\u0002', '');
  text = text.replaceAllMapped(_wrappedHyphen, (m) => '${m[1]}${m[2]}');

  // Any other control character is noise in a search query.
  text = text.replaceAll(_controlChars, ' ');

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
