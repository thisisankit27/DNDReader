import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  IntegrityError, buildReleases, fetchReleases, matchAsset, parseBodyChecksums, parseBodyCertFingerprint, compareSemver, parseSemver,
} from '../../src/lib/releases.mjs';

const dir = resolve(dirname(fileURLToPath(import.meta.url)), '../fixtures');
const fx = (n) => JSON.parse(readFileSync(resolve(dir, n), 'utf8'));
const base = 'https://github.com/thisisankit27/DNDReader/releases/download/v0.3.0/';

// An INDEPENDENT oracle: the table the owner supplied in the brief (typed there, not derived from the API).
// If the API ever disagreed with the release notes the owner wrote, this is what we compare against.
const OWNER_TABLE = {
  'dndreader_0.3.0-1_amd64.deb': [341628878, '2c04973edb4c16cab7189a0e99606edac337399e630f9acf9156dd6f7e4635fd'],
  'DNDReader-0.3.0-setup-x64.exe': [15556638, '880026ddcb5c39314a8734ab75ef6f9dea5eee9efb180979c568b0f9de594722'],
  'DNDReader-0.3.0-arm64-v8a.apk': [24858225, '61c26309ab37d4598eb1944b4fe92f65d18f29b985a093be57ba5fd8467e3788'],
  'DNDReader-0.3.0-armeabi-v7a.apk': [19911783, '4e215a1c9542fca632761834cda5d85186cd237e4974f9cefd0cd36611d8f5a5'],
  'DNDReader-0.3.0-x86_64.apk': [26550514, '1771ea8ac498bd275b5a1a53922b2354d9af4e58bfc2b20d3146aa9e809ccb56'],
};

test('live 0.3.0 snapshot: every file, size and hash equals the owner-supplied table', () => {
  const { releases } = buildReleases(fx('api-live-0.3.0.json'));
  assert.equal(releases.length, 1);
  const r = releases[0];
  assert.equal(r.version, '0.3.0');
  assert.equal(r.assets.length, 5);
  for (const a of r.assets) {
    const [bytes, sha] = OWNER_TABLE[a.filename];
    assert.equal(a.bytes, bytes, `${a.filename} size`);
    assert.equal(a.sha256, sha, `${a.filename} sha256`);
    assert.equal(a.url, base + a.filename);
    assert.equal(a.sha256Source, 'github-api');
  }
  assert.deepEqual(r.assets.map((a) => a.id).sort(), ['android-arm64-v8a', 'android-armeabi-v7a', 'android-x86_64', 'ubuntu-amd64', 'windows-x64']);
  assert.equal(r.certSha256, '90:B1:F8:9D:69:CA:9F:26:14:0A:AC:C9:DC:B2:A8:A5:BF:49:43:97:F1:BF:E1:99:A1:26:02:7F:A7:17:D9:36');
});

test('asset rules', () => {
  assert.deepEqual(matchAsset('dndreader_0.3.0-1_amd64.deb'), { platform: 'ubuntu', arch: 'amd64', format: 'deb', version: '0.3.0' });
  assert.equal(matchAsset('DNDReader-0.3.0-x86_64.apk').arch, 'x86_64');
  assert.equal(matchAsset('DNDReader-0.3.0-armeabi-v7a.apk').arch, 'armeabi-v7a');
  assert.equal(matchAsset('notes.txt'), null);
  assert.equal(matchAsset('DNDReader-0.3.0-setup-arm64.exe'), null);
});

test('semver ordering picks the highest, not the latest-published', () => {
  assert.ok(compareSemver(parseSemver('v0.10.0'), parseSemver('v0.9.9')) > 0);
  assert.equal(parseSemver('android-v0.3.0'), null);
  assert.equal(parseSemver('v0.3.0-rc1'), null);
});

test('two releases: newest first, older kept', () => {
  const { releases } = buildReleases(fx('api-two-releases-synthetic.json'));
  assert.deepEqual(releases.map((r) => r.version), ['0.3.1', '0.3.0']);
});

test('a release with a missing platform simply has no asset for it', () => {
  const { releases } = buildReleases(fx('api-no-windows-synthetic.json'));
  assert.equal(releases[0].assets.some((a) => a.platform === 'windows'), false);
  assert.equal(releases[0].assets.length, 4);
});

test('unknown files are ignored, not fatal', () => {
  const { releases, notes } = buildReleases(fx('api-extra-asset-synthetic.json'));
  assert.equal(releases[0].assets.length, 5);
  assert.ok(notes.some((n) => n.includes('notes.txt')));
});

test('drafts and pre-releases never become "latest"', () => {
  const { releases } = buildReleases(fx('api-prerelease-only-synthetic.json'));
  assert.equal(releases.length, 0);
});

test('checksum falls back to the release notes when the API has no digest', () => {
  const { releases } = buildReleases(fx('api-body-checksums-only-synthetic.json'));
  for (const a of releases[0].assets) {
    assert.equal(a.sha256, OWNER_TABLE[a.filename][1]);
    assert.equal(a.sha256Source, 'release-notes');
  }
});

test('no checksum anywhere stays null, never invented', () => {
  const { releases } = buildReleases(fx('api-no-checksums-synthetic.json'));
  for (const a of releases[0].assets) {
    assert.equal(a.sha256, null);
    assert.equal(a.sha256Source, null);
  }
});

test('INTEGRITY: digest and release notes disagreeing stops the build', () => {
  assert.throws(() => buildReleases(fx('api-digest-mismatch-synthetic.json')), (e) => e instanceof IntegrityError && /disagree/.test(e.message));
});

test('INTEGRITY: a download URL off this repository stops the build', () => {
  assert.throws(() => buildReleases(fx('api-foreign-url-synthetic.json')), (e) => e instanceof IntegrityError && /release path/.test(e.message));
});

test('INTEGRITY: a file named for another version stops the build', () => {
  assert.throws(() => buildReleases(fx('api-wrong-version-synthetic.json')), (e) => e instanceof IntegrityError && /named for 0\.2\.0/.test(e.message));
});

test('INTEGRITY: malformed size or digest stops the build', () => {
  const a = fx('api-live-0.3.0.json');
  a[0].assets[0].size = 12.5;
  assert.throws(() => buildReleases(a), IntegrityError);
  const b = fx('api-live-0.3.0.json');
  b[0].assets[0].digest = 'sha256:nothex';
  assert.throws(() => buildReleases(b), IntegrityError);
  assert.throws(() => buildReleases({ not: 'a list' }), IntegrityError);
});

test('body parsers', () => {
  const m = parseBodyChecksums(`${'a'.repeat(64)}  one.deb\n${'b'.repeat(64)} *two.exe\nnot a line`);
  assert.equal(m.get('one.deb'), 'a'.repeat(64));
  assert.equal(m.get('two.exe'), 'b'.repeat(64));
  assert.equal(parseBodyCertFingerprint('no fingerprint'), null);
});

// ---- the network layer: every outage becomes {ok:false}, never a throw, never invented data ----

const res = (status, headers = {}, json = []) => ({ ok: status >= 200 && status < 300, status, headers: new Headers(headers), json: async () => json });
const noSleep = async () => {};

test('fetch: success', async () => {
  const r = await fetchReleases({ fetchImpl: async () => res(200, {}, [1]), sleep: noSleep });
  assert.deepEqual(r, { ok: true, json: [1] });
});

test('fetch: transient 503 is retried and then succeeds', async () => {
  let n = 0;
  const r = await fetchReleases({ fetchImpl: async () => (++n < 3 ? res(503) : res(200, {}, [])), sleep: noSleep });
  assert.equal(r.ok, true);
  assert.equal(n, 3);
});

test('fetch: persistent 5xx degrades with the reason', async () => {
  const r = await fetchReleases({ fetchImpl: async () => res(503), sleep: noSleep });
  assert.equal(r.ok, false);
  assert.match(r.error, /503/);
});

test('fetch: rate limit that resets far in the future gives up at once instead of waiting', async () => {
  let n = 0;
  const r = await fetchReleases({
    fetchImpl: async () => (n++, res(403, { 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': String(Math.floor(Date.now() / 1000) + 3000) })),
    sleep: noSleep,
  });
  assert.equal(r.ok, false);
  assert.equal(n, 1);
  assert.match(r.error, /rate limited/);
});

test('fetch: a short Retry-After is honoured', async () => {
  const waits = [];
  let n = 0;
  const r = await fetchReleases({
    fetchImpl: async () => (++n === 1 ? res(429, { 'retry-after': '2' }) : res(200, {}, [])),
    sleep: async (ms) => { waits.push(ms); },
  });
  assert.equal(r.ok, true);
  assert.deepEqual(waits, [2000]);
});

test('fetch: network failure and bad JSON and 404 all degrade', async () => {
  const a = await fetchReleases({ fetchImpl: async () => { throw new Error('ECONNRESET'); }, sleep: noSleep });
  assert.equal(a.ok, false);
  assert.match(a.error, /network error/);
  const b = await fetchReleases({ fetchImpl: async () => ({ ok: true, status: 200, headers: new Headers(), json: async () => { throw new Error('x'); } }), sleep: noSleep });
  assert.match(b.error, /not valid JSON/);
  let n = 0;
  const c = await fetchReleases({ fetchImpl: async () => (n++, res(404)), sleep: noSleep });
  assert.equal(c.ok, false);
  assert.equal(n, 1, '404 is not retried');
});
