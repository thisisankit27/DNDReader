import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectPlatform, archWarning } from '../../src/lib/detect.js';
import { formatSize, formatBytes, formatDate } from '../../src/lib/format.js';

// Real-world user-agent strings. The expectation is a SUGGESTION, never a decision.
const UA = [
  ['Android Chrome (Moto G60)', 'Mozilla/5.0 (Linux; Android 12; moto g60) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36', 0, 'android'],
  ['Android Firefox', 'Mozilla/5.0 (Android 14; Mobile; rv:130.0) Gecko/130.0 Firefox/130.0', 0, 'android'],
  ['Samsung Internet', 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36', 0, 'android'],
  ['Windows Chrome', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36', 0, 'windows'],
  ['Windows Edge', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0', 0, 'windows'],
  ['Windows Firefox', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0', 0, 'windows'],
  ['Ubuntu Firefox', 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0', 0, 'ubuntu'],
  ['Linux Chrome (distro unknown)', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36', 0, 'ubuntu'],
  ['Linux on ARM', 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36', 0, 'ubuntu'],
  ['macOS Safari', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15', 0, 'macos'],
  ['iPhone Safari', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1', 5, 'ios'],
  ['iPad asking for the desktop site (reports a Mac)', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15', 5, 'ios'],
  ['ChromeOS', 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36', 0, 'chromeos'],
  ['Googlebot', 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)', 0, 'unknown'],
  ['empty', '', 0, 'unknown'],
  ['something unrecognised', 'SomeBrowser/1.0 (PlayStation 5)', 0, 'unknown'],
];
for (const [name, ua, touch, want] of UA) {
  test(`detect: ${name} -> ${want}`, () => assert.equal(detectPlatform(ua, touch).platform, want));
}

test('detect: a Linux that does not say Ubuntu is flagged as unsure, one that does is not', () => {
  assert.equal(detectPlatform(UA[7][1]).distroUnsure, true);
  assert.equal(detectPlatform(UA[6][1]).distroUnsure, false);
});

test('arch warning only fires on positive evidence', () => {
  assert.equal(archWarning({ architecture: 'arm', bitness: '64' }), 'arm');
  assert.equal(archWarning({ architecture: 'x86', bitness: '32' }), 'x86-32');
  assert.equal(archWarning({ architecture: 'x86', bitness: '64' }), null);
  assert.equal(archWarning(undefined), null, 'Firefox/Safari give no hints: say nothing');
});

test('sizes: one wording, decimal units, matching what browsers show', () => {
  assert.equal(formatSize(341628878), '342 MB');
  assert.equal(formatSize(24858225), '24.9 MB');
  assert.equal(formatSize(15556638), '15.6 MB');
  assert.equal(formatSize(19911783), '19.9 MB');
  assert.equal(formatSize(26550514), '26.6 MB');
  assert.equal(formatSize(512_000), '512 KB');
  assert.equal(formatSize(NaN), '');
  assert.equal(formatBytes(341628878), '341,628,878 bytes');
});

test('dates are UTC and stable', () => {
  assert.equal(formatDate('2026-10-19T11:14:59Z'), '19 October 2026');
  assert.equal(formatDate('garbage'), '');
});
