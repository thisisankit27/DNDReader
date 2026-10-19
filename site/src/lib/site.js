// Build-time view of the release data. Pages branch on `status`, never on a hard-coded version.
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import pin from '../data/signing-key.json';
import { formatSize, formatBytes, formatDate } from './format.js';

function load() {
  const p = resolve(process.cwd(), 'src/data/releases.generated.json');
  if (!existsSync(p)) {
    return { status: 'unavailable', source: 'missing', error: 'releases.generated.json is missing (run `npm run releases`)', releases: [] };
  }
  return JSON.parse(readFileSync(p, 'utf8'));
}

const data = load();

export const status = data.status; // 'ok' | 'no-releases' | 'unavailable'
export const source = data.source;
export const releases = data.releases ?? [];
export const latest = status === 'ok' ? (releases[0] ?? null) : null;
export const older = latest ? releases.slice(1) : [];

export const repo = 'thisisankit27/DNDReader';
export const repoUrl = `https://github.com/${repo}`;
export const issuesUrl = `${repoUrl}/issues`;
export const releasesUrl = `${repoUrl}/releases/latest`; // the ONE GitHub page a visitor can land on: the failure fallback
export const licenseUrl = `${repoUrl}/blob/main/LICENSE`;
export const certFingerprint = pin.android.sha256;

const ANDROID_ORDER = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

/** Files of one platform in a release, best default first (Android: arm64-v8a, then the rest). */
export function assetsFor(platform, release = latest) {
  if (!release) return [];
  const list = release.assets.filter((a) => a.platform === platform);
  if (platform === 'android') list.sort((a, b) => ANDROID_ORDER.indexOf(a.arch) - ANDROID_ORDER.indexOf(b.arch));
  return list.map(decorate);
}

export function decorate(a) {
  return { ...a, size: formatSize(a.bytes), exactBytes: formatBytes(a.bytes) };
}

export const publishedOn = latest ? formatDate(latest.publishedAt) : '';

/** What the client script needs to turn the hero button into a direct download. */
export function clientData() {
  const out = {};
  for (const p of ['ubuntu', 'windows', 'android']) {
    const a = assetsFor(p)[0];
    if (a) out[p] = { filename: a.filename, url: a.url, size: a.size, arch: a.arch, version: latest.version };
  }
  return out;
}
