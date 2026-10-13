#!/usr/bin/env bash
# Generates the three PDF fixtures from local HTML with headless Chrome.
# Original text only; no personal documents are used. Output: prose.pdf,
# technical.pdf, two_column.pdf next to this script.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chrome="${CHROME:-google-chrome}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

CHROME_EXTRA=
render() { # render <html> <pdf>
  "$chrome" --headless=new --disable-gpu --no-sandbox --no-pdf-header-footer \
    $CHROME_EXTRA \
    --print-to-pdf="$2" "file://$1" >/dev/null 2>&1
}

para() { # a paragraph that exercises ligatures (fi fl ffi ffl ff), long words and hyphen wraps
  cat <<'P'
<p>The office staff found the efficient workflow difficult to justify until the official
affluent donors reviewed the findings. Idiopathic pulmonary fibrosis is a chronic, progressive
lung disease; pneumono&shy;ultra&shy;microscopic&shy;silico&shy;volcano&shy;coniosis is a famously long word, and
electro&shy;encephalo&shy;graphically unrelated terms such as counter&shy;intuitively, un&shy;characteristically and
incompre&shy;hensi&shy;bilities appear here to force line-wrap hyphenation at the margins. Pre- and
post-operative care, a state-of-the-art device, and a well-known "quoted phrase" — set off by an
em-dash — all appear so that selection tests see real compound hyphens, quotes and dashes.</p>
P
}

cat >"$work/prose.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
 @page { margin: 22mm; }
 body { font: 12.5pt/1.55 "Liberation Serif","DejaVu Serif",serif; width: 105mm;
        text-align: justify; hyphens: auto; font-variant-ligatures: common-ligatures; }
 h1 { font-size: 20pt; hyphens: manual; }
</style></head><body><h1>Prose fixture</h1>
$(for i in 1 2 3 4 5 6; do para; done)
</body></html>
HTML

cat >"$work/technical.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
 @page { margin: 20mm; }
 body { font: 11pt/1.5 "Liberation Sans","DejaVu Sans",sans-serif; }
 code, pre { font-family: "Liberation Mono","DejaVu Sans Mono",monospace; font-size: 9.5pt; }
 pre { background:#f2f2f2; padding:6px; } table { border-collapse: collapse; }
 td, th { border:1px solid #888; padding:3px 8px; } h2 { break-after: avoid; }
</style></head><body>
<h1>Technical article fixture</h1>
<h2>1. Introduction</h2>
$(para)
<h2>2. Method</h2>
<p>Let x<sup>2</sup> + y<sup>2</sup> = z<sup>2</sup> hold [12]. See https://example.org/a/b?c=d&amp;e=f for details;
the p-value was &lt; 0.05 (95% CI 1.2&ndash;3.4).</p>
<pre>for (int i = 0; i &lt; n; ++i) {
  total += weights[i] * samples[i];
}</pre>
<table><tr><th>Cohort</th><th>n</th><th>Mean</th></tr>
<tr><td>Control</td><td>120</td><td>3.4</td></tr><tr><td>Treated</td><td>118</td><td>4.1</td></tr></table>
<h2>3. Discussion</h2>
$(para)$(para)
</body></html>
HTML

cat >"$work/two_column.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
 @page { margin: 18mm; }
 body { font: 10.5pt/1.45 "Liberation Serif","DejaVu Serif",serif; column-count: 2; column-gap: 12mm;
        text-align: justify; hyphens: auto; font-variant-ligatures: common-ligatures; }
 h1 { column-span: all; }
</style></head><body><h1>Two-column fixture</h1>
$(for i in 1 2 3 4 5 6 7 8; do para; done)
</body></html>
HTML

# Nested headings, one chapter per page: the table-of-contents fixture.
cat >"$work/outline.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
 @page { margin: 22mm; }
 body { font: 12pt/1.5 "Liberation Serif","DejaVu Serif",serif; }
 section { break-after: page; }
</style></head><body>
<section><h1>Chapter One</h1><h2>First section</h2><p>Opening text of chapter one.</p>
<h2>Second section</h2><p>More text in chapter one.</p></section>
<section><h1>Chapter Two</h1><h2>Methods</h2><p>Opening text of chapter two.</p></section>
<section><h1>Chapter Three</h1><h2>Results</h2><p>Opening text of chapter three.</p>
<h2>Discussion</h2><p>Closing text.</p></section>
</body></html>
HTML

for n in prose technical two_column; do
  render "$work/$n.html" "$here/$n.pdf"
  echo "wrote $here/$n.pdf ($(stat -c %s "$here/$n.pdf") bytes)"
done

# Only this fixture carries a document outline (bookmarks).
CHROME_EXTRA="--export-tagged-pdf --generate-pdf-document-outline"
render "$work/outline.html" "$here/outline.pdf"
echo "wrote $here/outline.pdf ($(stat -c %s "$here/outline.pdf") bytes)"
