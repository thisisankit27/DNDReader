// The Android signing-certificate fingerprint is shown on the Android page as the proof that a file came
// from this project. Three places must agree, and this fails loudly if they do not:
//   1. site/src/data/signing-key.json                     (what the site shows)
//   2. EXPECTED_CERT_SHA256 in android-release.yml         (what the release pipeline enforces; READ ONLY here)
//   3. the fingerprint printed in the latest release notes (what people were told)
// A disagreement is an integrity event, not a bug to patch: do not edit one value to match another.
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pin = JSON.parse(readFileSync(resolve(root, 'src/data/signing-key.json'), 'utf8')).android.sha256;
const norm = (s) => s.replace(/:/g, '').toLowerCase();
const problems = [];

if (!/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(pin)) problems.push(`signing-key.json: "${pin}" is not a colon-separated SHA-256`);

const wf = resolve(root, '../.github/workflows/android-release.yml');
if (existsSync(wf)) {
  const m = /EXPECTED_CERT_SHA256:\s*([0-9a-fA-F]{64})/.exec(readFileSync(wf, 'utf8'));
  if (!m) problems.push('android-release.yml: EXPECTED_CERT_SHA256 not found (the workflow changed shape; update this check deliberately)');
  else if (norm(pin) !== m[1].toLowerCase()) problems.push(`signing-key.json (${pin}) does not match android-release.yml EXPECTED_CERT_SHA256 (${m[1]})`);
} else {
  console.warn('check-signing-pin: android-release.yml not found (a partial checkout?); skipping that comparison');
}

const gen = resolve(root, 'src/data/releases.generated.json');
if (existsSync(gen)) {
  const data = JSON.parse(readFileSync(gen, 'utf8'));
  const printed = data.releases?.[0]?.certSha256;
  if (printed && norm(printed) !== norm(pin)) problems.push(`the latest release notes print ${printed}, which does not match the pinned ${pin}`);
  else if (!printed && data.status === 'ok') console.warn('check-signing-pin: the latest release notes print no certificate fingerprint; nothing to compare');
}

if (problems.length) {
  console.error('\nSIGNING-KEY INTEGRITY ERROR\n' + problems.map((p) => '  - ' + p).join('\n') + '\nInvestigate before anything ships.\n');
  process.exit(1);
}
console.log('signing pin: consistent across signing-key.json, android-release.yml and the release notes');
