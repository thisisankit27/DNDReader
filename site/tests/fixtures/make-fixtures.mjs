// Builds every release-data fixture from ONE real snapshot of the GitHub API (api-live-0.3.0.json, taken
// 2026-10-19), trimmed to the fields the site reads. Variants are synthetic and say so in their names.
//   node tests/fixtures/make-fixtures.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));
const live = JSON.parse(readFileSync(resolve(dir, 'api-live-0.3.0.json'), 'utf8'));

const trim = (r) => ({
  tag_name: r.tag_name, name: r.name, draft: r.draft, prerelease: r.prerelease, published_at: r.published_at, body: r.body,
  assets: r.assets.map((a) => ({ name: a.name, content_type: a.content_type, state: a.state, size: a.size, digest: a.digest, browser_download_url: a.browser_download_url })),
});
const base = live.map(trim);
const out = (name, data) => writeFileSync(resolve(dir, name), JSON.stringify(data, null, 2) + '\n');
const clone = (x) => JSON.parse(JSON.stringify(x));

out('api-live-0.3.0.json', base); // real data, trimmed

// synthetic: a newer release 0.3.1 beside 0.3.0 (hashes are fake, clearly so)
{
  const r = clone(base[0]);
  r.tag_name = 'v0.3.1'; r.name = 'DNDReader 0.3.1 (synthetic fixture)'; r.published_at = '2026-11-02T09:00:00Z';
  r.body = 'Synthetic fixture release.';
  r.assets = r.assets.map((a, i) => {
    const name = a.name.replace(/0\.3\.0/g, '0.3.1');
    return { ...a, name, digest: 'sha256:' + String(i + 1).repeat(64).slice(0, 64), browser_download_url: `https://github.com/thisisankit27/DNDReader/releases/download/v0.3.1/${name}` };
  });
  out('api-two-releases-synthetic.json', [r, ...base]);
}
// synthetic: Windows installer missing from the latest release
{ const r = clone(base[0]); r.assets = r.assets.filter((a) => !a.name.endsWith('.exe')); out('api-no-windows-synthetic.json', [r]); }
// synthetic: an extra file no rule matches (must be ignored, not break the build)
{ const r = clone(base[0]); r.assets.push({ ...r.assets[0], name: 'notes.txt', browser_download_url: 'https://github.com/thisisankit27/DNDReader/releases/download/v0.3.0/notes.txt', digest: null, size: 10 }); out('api-extra-asset-synthetic.json', [r]); }
// synthetic: only a pre-release and a draft exist
{ const r = clone(base[0]); r.prerelease = true; const d = clone(base[0]); d.draft = true; d.tag_name = 'v0.4.0'; out('api-prerelease-only-synthetic.json', [r, d]); }
// synthetic: API has no digest, the release notes carry the checksums (fallback path)
{ const r = clone(base[0]); r.assets.forEach((a) => { a.digest = null; }); out('api-body-checksums-only-synthetic.json', [r]); }
// synthetic: neither source has a checksum (the page must say so and show none)
{ const r = clone(base[0]); r.assets.forEach((a) => { a.digest = null; }); r.body = 'No checksums here.'; out('api-no-checksums-synthetic.json', [r]); }
// INTEGRITY: digest and release notes disagree (build must fail)
{ const r = clone(base[0]); r.assets[0].digest = 'sha256:' + '0'.repeat(64); out('api-digest-mismatch-synthetic.json', [r]); }
// INTEGRITY: a download URL that is not this repository's release path (build must fail)
{ const r = clone(base[0]); r.assets[0].browser_download_url = 'https://evil.example/DNDReader-0.3.0-arm64-v8a.apk'; out('api-foreign-url-synthetic.json', [r]); }
// INTEGRITY: a file named for another version attached to this release (build must fail)
{ const r = clone(base[0]); r.assets[0].name = 'DNDReader-0.2.0-arm64-v8a.apk'; r.assets[0].browser_download_url = 'https://github.com/thisisankit27/DNDReader/releases/download/v0.3.0/DNDReader-0.2.0-arm64-v8a.apk'; out('api-wrong-version-synthetic.json', [r]); }
out('api-empty.json', []);
out('api-rate-limited.json', { __fail: { status: 403, headers: { 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '4102444800' } } });
out('api-server-error.json', { __fail: { status: 503 } });
out('api-network-down.json', { __network: true });
console.log('fixtures written');
