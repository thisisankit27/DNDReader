// The build-time script end to end, through the real code path, with each fixture. Integrity problems must
// stop the build (exit 1); outages must not (exit 0, status "unavailable"). CI=1 so no local cache is read.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
function run(fixture) {
  const out = join(mkdtempSync(join(tmpdir(), 'dnd-rel-')), 'out.json');
  const gho = join(dirname(out), 'gh-output');
  writeFileSync(gho, '');
  const r = spawnSync(process.execPath, ['scripts/fetch-releases.mjs'], {
    cwd: root, encoding: 'utf8',
    env: { ...process.env, CI: '1', RELEASES_FIXTURE: `tests/fixtures/${fixture}`, RELEASES_OUT: out, GITHUB_OUTPUT: gho },
  });
  let data = null;
  try { data = JSON.parse(readFileSync(out, 'utf8')); } catch {}
  return { code: r.status, stderr: r.stderr, stdout: r.stdout, data, output: readFileSync(gho, 'utf8') };
}

for (const [fixture, status] of [
  ['api-live-0.3.0.json', 'ok'], ['api-two-releases-synthetic.json', 'ok'], ['api-no-windows-synthetic.json', 'ok'],
  ['api-empty.json', 'no-releases'], ['api-prerelease-only-synthetic.json', 'no-releases'],
  ['api-rate-limited.json', 'unavailable'], ['api-server-error.json', 'unavailable'], ['api-network-down.json', 'unavailable'],
]) {
  test(`${fixture}: exits 0, status "${status}", and tells the workflow`, () => {
    const r = run(fixture);
    assert.equal(r.code, 0, r.stderr);
    assert.equal(r.data.status, status);
    assert.equal(r.data.source, 'fixture');
    assert.match(r.output, new RegExp(`data_status=${status}`));
    if (status !== 'ok') assert.deepEqual(r.data.releases, [], 'no release data is invented when there is none');
  });
}

for (const fixture of ['api-digest-mismatch-synthetic.json', 'api-foreign-url-synthetic.json', 'api-wrong-version-synthetic.json']) {
  test(`${fixture}: INTEGRITY ERROR, exit 1, and no data file is written`, () => {
    const r = run(fixture);
    assert.equal(r.code, 1);
    assert.match(r.stderr, /INTEGRITY ERROR - refusing to build/);
    assert.equal(r.data, null);
    assert.equal(r.output, '', 'the deploy gate is never told "ok"');
  });
}

test('an unavailable CI run never reads a stale cache', () => {
  const r = run('api-network-down.json');
  assert.equal(r.data.source, 'fixture');
  assert.equal(r.data.status, 'unavailable');
  assert.match(r.data.error, /network/);
});
