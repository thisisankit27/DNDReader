// Generates src/data/releases.generated.json from the GitHub Releases API. Run by `npm run build`.
//
//   status ok           releases found; the site renders them
//   status no-releases  the API answered with nothing publishable
//   status unavailable  the API could not be reached (rate limit, 5xx, offline). The site still builds, in
//                       a degraded form with no version, size or checksum, and the deploy job is skipped
//                       so the last good site stays live.
//
// Exit code 1 only for an INTEGRITY error (see releases.mjs): that is a bug or an incident, not an outage.
//
// Test hook: RELEASES_FIXTURE=<file> replaces the network. The file holds either the API's JSON array, or
// {"__fail": {"status": 403, "headers": {...}}}, or {"__network": true}.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { appendFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { IntegrityError, buildReleases, fetchReleases, toGeneratedFile } from '../src/lib/releases.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = process.env.RELEASES_OUT ? resolve(process.env.RELEASES_OUT) : resolve(root, 'src/data/releases.generated.json');
const CACHE = resolve(root, '.cache/releases.json');
const inCI = Boolean(process.env.CI);

function token() {
  const t = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  if (t) return t;
  try {
    return execFileSync('gh', ['auth', 'token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

async function fixtureFetch(path) {
  const data = JSON.parse(await readFile(path, 'utf8'));
  return async () => {
    if (data && data.__network) throw new Error('fixture: network unreachable');
    if (data && data.__fail) {
      const { status = 500, headers = {} } = data.__fail;
      return { ok: false, status, headers: new Headers(headers), json: async () => ({}) };
    }
    return { ok: true, status: 200, headers: new Headers(), json: async () => data };
  };
}

async function main() {
  const fixture = process.env.RELEASES_FIXTURE;
  const generatedAt = new Date().toISOString();
  let file;

  const result = await fetchReleases({
    token: fixture ? '' : token(),
    fetchImpl: fixture ? await fixtureFetch(resolve(process.cwd(), fixture)) : fetch,
    sleep: fixture ? async () => {} : undefined,
  });
  const source = fixture ? 'fixture' : 'github-api';

  if (result.ok) {
    const { releases, notes } = buildReleases(result.json);
    file = toGeneratedFile({ status: releases.length ? 'ok' : 'no-releases', source, releases, notes, generatedAt });
    if (!fixture && releases.length) {
      await mkdir(dirname(CACHE), { recursive: true });
      await writeFile(CACHE, JSON.stringify(file, null, 2));
    }
  } else if (!inCI && !fixture && existsSync(CACHE)) {
    // Local convenience only. CI never reads a cache: a deploy must reflect GitHub, not a leftover file.
    file = JSON.parse(await readFile(CACHE, 'utf8'));
    file = { ...file, source: 'cache', error: result.error };
    console.warn(`releases: ${result.error}; using the cached copy from ${file.generatedAt} (local build only)`);
  } else {
    file = toGeneratedFile({ status: 'unavailable', source, error: result.error, generatedAt });
    console.warn(`releases: UNAVAILABLE (${result.error}). The site will build without version, size or checksum data.`);
  }

  await mkdir(dirname(OUT), { recursive: true });
  await writeFile(OUT, JSON.stringify(file, null, 2) + '\n');

  const latest = file.releases?.[0];
  console.log(
    `releases: status=${file.status} source=${file.source}` +
      (latest ? ` latest=${latest.version} assets=${latest.assets.length}` : '') +
      (file.releases?.length > 1 ? ` older=${file.releases.length - 1}` : ''),
  );
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `data_status=${file.status}\n`);
}

main().catch((e) => {
  if (e instanceof IntegrityError) {
    console.error(`\nINTEGRITY ERROR - refusing to build.\n${e.message}\n`);
  } else {
    console.error(e);
  }
  process.exit(1);
});
