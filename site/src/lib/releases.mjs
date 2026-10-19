// Release data: turns the GitHub Releases API response into the one model the site renders.
// Pure functions, no I/O except the injectable fetch, so every failure path is unit-tested.
//
// Nothing here invents data. A missing checksum stays missing; a disagreement between two sources of
// the same checksum, a file named for another version, or a download URL that is not this repository's
// release path is an INTEGRITY error and stops the build. An outage (rate limit, 5xx, no network) is
// different: it yields status "unavailable" and the site degrades honestly (see degrade in site.js).

export const REPO = 'thisisankit27/DNDReader';

export class IntegrityError extends Error {
  constructor(message) {
    super(message);
    this.name = 'IntegrityError';
  }
}

/**
 * One table maps a release file to a platform. A new release of the same files needs no code change;
 * a new platform is one rule here plus its page.
 */
export const ASSET_RULES = [
  { re: /^dndreader_(?<v>\d+\.\d+\.\d+)-\d+_amd64\.deb$/, platform: 'ubuntu', arch: 'amd64', format: 'deb' },
  { re: /^DNDReader-(?<v>\d+\.\d+\.\d+)-setup-x64\.exe$/, platform: 'windows', arch: 'x64', format: 'exe' },
  {
    re: /^DNDReader-(?<v>\d+\.\d+\.\d+)-(?<abi>arm64-v8a|armeabi-v7a|x86_64)\.apk$/,
    platform: 'android',
    arch: null, // taken from the ABI group
    format: 'apk',
  },
];

export function matchAsset(name) {
  for (const rule of ASSET_RULES) {
    const m = rule.re.exec(name);
    if (m) {
      return { platform: rule.platform, arch: rule.arch ?? m.groups.abi, format: rule.format, version: m.groups.v };
    }
  }
  return null;
}

export function parseSemver(tag) {
  const m = /^v(\d+)\.(\d+)\.(\d+)$/.exec(tag ?? '');
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

export function compareSemver(a, b) {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}

const SHA256 = /^[0-9a-f]{64}$/;
const CERT = /\b([0-9A-F]{2}(?::[0-9A-F]{2}){31})\b/;

/** "<64 hex>  <filename>" lines from a release body, as `sha256sum` prints them. */
export function parseBodyChecksums(body) {
  const out = new Map();
  for (const line of String(body ?? '').split(/\r?\n/)) {
    const m = /^([0-9a-f]{64})\s+\*?(\S+)\s*$/.exec(line.trim());
    if (m) out.set(m[2], m[1]);
  }
  return out;
}

/** The colon-separated certificate fingerprint printed in release notes, if any. */
export function parseBodyCertFingerprint(body) {
  const m = CERT.exec(String(body ?? ''));
  return m ? m[1] : null;
}

function validateAsset(a, tag, repo) {
  if (typeof a.name !== 'string' || !a.name) throw new IntegrityError(`${tag}: an asset has no name`);
  if (!Number.isSafeInteger(a.size) || a.size <= 0) {
    throw new IntegrityError(`${tag}/${a.name}: size must be a positive integer, got ${JSON.stringify(a.size)}`);
  }
  const expected = `https://github.com/${repo}/releases/download/${tag}/${a.name}`;
  if (a.browser_download_url !== expected) {
    throw new IntegrityError(
      `${tag}/${a.name}: download URL is not this repository's release path.\n  expected ${expected}\n  got      ${a.browser_download_url}`,
    );
  }
  return expected;
}

/**
 * apiReleases: the parsed JSON array from GET /repos/{repo}/releases.
 * Returns { releases, notes } newest first. Throws IntegrityError on anything that must not ship.
 */
export function buildReleases(apiReleases, { repo = REPO } = {}) {
  if (!Array.isArray(apiReleases)) throw new IntegrityError('the releases response is not a list');
  const releases = [];
  const notes = [];

  for (const r of apiReleases) {
    if (r.draft || r.prerelease) {
      notes.push(`skipped ${r.tag_name}: ${r.draft ? 'draft' : 'pre-release'}`);
      continue;
    }
    const sv = parseSemver(r.tag_name);
    if (!sv) {
      notes.push(`skipped ${r.tag_name}: not a vMAJOR.MINOR.PATCH release tag`);
      continue;
    }
    const version = sv.join('.');
    const bodySums = parseBodyChecksums(r.body);
    const assets = [];
    const seen = new Set();

    for (const a of r.assets ?? []) {
      if (a.state && a.state !== 'uploaded') {
        notes.push(`skipped ${a.name}: upload state is ${a.state}`);
        continue;
      }
      const hit = matchAsset(a.name);
      if (!hit) {
        notes.push(`ignored ${a.name}: no platform rule matches`);
        continue;
      }
      if (hit.version !== version) {
        throw new IntegrityError(`${r.tag_name}/${a.name}: the file is named for ${hit.version}, not ${version}`);
      }
      const url = validateAsset(a, r.tag_name, repo);

      let fromApi = null;
      if (a.digest != null) {
        const m = /^sha256:([0-9a-f]{64})$/.exec(a.digest);
        if (!m) throw new IntegrityError(`${r.tag_name}/${a.name}: malformed digest ${JSON.stringify(a.digest)}`);
        fromApi = m[1];
      }
      const fromBody = bodySums.get(a.name) ?? null;
      if (fromBody && !SHA256.test(fromBody)) throw new IntegrityError(`${r.tag_name}/${a.name}: malformed body checksum`);
      if (fromApi && fromBody && fromApi !== fromBody) {
        throw new IntegrityError(
          `${r.tag_name}/${a.name}: the API digest and the checksum in the release notes disagree.\n  api  ${fromApi}\n  body ${fromBody}`,
        );
      }

      const id = `${hit.platform}-${hit.arch}`;
      if (seen.has(id)) throw new IntegrityError(`${r.tag_name}: two files match ${id}`);
      seen.add(id);

      assets.push({
        id,
        platform: hit.platform,
        arch: hit.arch,
        format: hit.format,
        filename: a.name,
        url,
        bytes: a.size,
        sha256: fromApi ?? fromBody, // null when neither source has one: the site then says so
        sha256Source: fromApi ? 'github-api' : fromBody ? 'release-notes' : null,
        contentType: a.content_type ?? null,
      });
    }

    releases.push({
      version,
      tag: r.tag_name,
      name: r.name ?? r.tag_name,
      publishedAt: r.published_at ?? null,
      notesUrl: `https://github.com/${repo}/releases/tag/${r.tag_name}`,
      certSha256: parseBodyCertFingerprint(r.body),
      assets,
      _sv: sv,
    });
  }

  releases.sort((a, b) => compareSemver(b._sv, a._sv));
  for (const r of releases) delete r._sv;
  return { releases, notes };
}

const sleepReal = (ms) => new Promise((res) => setTimeout(res, ms));

/**
 * Fetch the releases list with retries. Never throws for an outage: returns
 * { ok: false, error } so the caller can degrade. fetchImpl and sleep are injectable.
 */
export async function fetchReleases({
  repo = REPO,
  token = '',
  fetchImpl = fetch,
  sleep = sleepReal,
  attempts = 3,
  maxWaitMs = 30_000,
  now = () => Date.now(),
} = {}) {
  const url = `https://api.github.com/repos/${repo}/releases?per_page=30`;
  const headers = { accept: 'application/vnd.github+json', 'user-agent': 'dndreader-site-build', 'x-github-api-version': '2022-11-28' };
  if (token) headers.authorization = `Bearer ${token}`;

  let lastError = 'no attempt was made';
  for (let attempt = 1; attempt <= attempts; attempt++) {
    let res;
    try {
      res = await fetchImpl(url, { headers });
    } catch (e) {
      lastError = `network error: ${e?.message ?? e}`;
      if (attempt < attempts) await sleep(1000 * 2 ** (attempt - 1));
      continue;
    }

    if (res.ok) {
      try {
        return { ok: true, json: await res.json() };
      } catch {
        return { ok: false, error: 'the response was not valid JSON' };
      }
    }

    lastError = `GitHub answered ${res.status}`;
    const retryable = res.status >= 500 || res.status === 403 || res.status === 429;
    if (!retryable) return { ok: false, error: lastError };

    // Rate limit: wait if the wait is short, otherwise give up (the deploy is then skipped).
    let waitMs = 1000 * 2 ** (attempt - 1);
    const retryAfter = Number(res.headers.get('retry-after'));
    const reset = Number(res.headers.get('x-ratelimit-reset'));
    const remaining = res.headers.get('x-ratelimit-remaining');
    if (Number.isFinite(retryAfter) && retryAfter > 0) waitMs = retryAfter * 1000;
    else if (remaining === '0' && Number.isFinite(reset) && reset > 0) waitMs = Math.max(0, reset * 1000 - now());
    if (waitMs > maxWaitMs) return { ok: false, error: `${lastError} (rate limited; the limit resets in ${Math.ceil(waitMs / 1000)} s)` };
    if (attempt < attempts) await sleep(waitMs);
  }
  return { ok: false, error: lastError };
}

/** The file the site reads. status is the only thing pages branch on. */
export function toGeneratedFile({ status, source, releases = [], error = null, notes = [], generatedAt }) {
  return { schema: 1, status, source, generatedAt, repo: REPO, error, notes, releases };
}
