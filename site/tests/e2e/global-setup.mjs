import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { VARIANTS } from './variants.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const out = resolve(root, '.build-out');

export default async function globalSetup() {
  if (process.env.PW_REUSE_BUILDS && existsSync(out)) return;
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  for (const [name, v] of Object.entries(VARIANTS)) {
    if (v.network && process.env.SKIP_NETWORK) continue;
    const env = {
      ...process.env,
      CI: '1', // never read a local cache: every variant reflects exactly its fixture (or the live API)
      ASTRO_TELEMETRY_DISABLED: '1',
      SITE_BASE: v.base,
      OUT_DIR: resolve(out, name),
      ...(v.siteUrl ? { SITE_URL: v.siteUrl } : { SITE_URL: '' }),
      ...(v.fixture ? { RELEASES_FIXTURE: `tests/fixtures/${v.fixture}` } : { RELEASES_FIXTURE: '' }),
    };
    if (!v.siteUrl) delete env.SITE_URL;
    if (!v.fixture) delete env.RELEASES_FIXTURE;
    const run = (args) => execFileSync(process.execPath, args, { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
    run(['scripts/fetch-releases.mjs']);
    copyFileSync(resolve(root, 'src/data/releases.generated.json'), resolve(out, `${name}.releases.json`));
    run([resolve(root, 'node_modules/astro/bin/astro.mjs'), 'build', '--silent']);
  }
}
