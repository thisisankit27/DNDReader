import { readFileSync } from 'node:fs';
import { test, expect, UA } from './fixtures';

const text = async (page: any, path: string, s: any) => {
  await page.goto(s.url(path));
  return page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
};
// The pinned Android signing-certificate fingerprint is a property of the key, not of a release, so it is
// legitimately present even when release data is not. It is removed before asserting "no checksum shown".
const CERT = /90b1f89d69ca9f26140aacc9dcb2a8a5bf494397f1bfe199a126027fa717d936/g;
const html = (s: any, path: string) => readFileSync(`${s.dir}/${path}index.html`, 'utf8').replace(CERT, '[cert]');
const OWNER = {
  'dndreader_0.3.0-1_amd64.deb': '2c04973edb4c16cab7189a0e99606edac337399e630f9acf9156dd6f7e4635fd',
  'DNDReader-0.3.0-setup-x64.exe': '880026ddcb5c39314a8734ab75ef6f9dea5eee9efb180979c568b0f9de594722',
  'DNDReader-0.3.0-arm64-v8a.apk': '61c26309ab37d4598eb1944b4fe92f65d18f29b985a093be57ba5fd8467e3788',
  'DNDReader-0.3.0-armeabi-v7a.apk': '4e215a1c9542fca632761834cda5d85186cd237e4974f9cefd0cd36611d8f5a5',
  'DNDReader-0.3.0-x86_64.apk': '1771ea8ac498bd275b5a1a53922b2354d9af4e58bfc2b20d3146aa9e809ccb56',
};

test.describe('the happy path renders the real data', () => {
  test('every hash, size and file name on the pages equals the owner-supplied table', async ({ page, sites }) => {
    const s = await sites('snap');
    const pages = { ubuntu: ['dndreader_0.3.0-1_amd64.deb'], windows: ['DNDReader-0.3.0-setup-x64.exe'], android: ['DNDReader-0.3.0-arm64-v8a.apk', 'DNDReader-0.3.0-armeabi-v7a.apk', 'DNDReader-0.3.0-x86_64.apk'] };
    for (const [p, files] of Object.entries(pages)) {
      const t = await text(page, `download/${p}/`, s);
      for (const f of files) {
        expect(t, `${p}: ${f}`).toContain(f);
        expect(t, `${p}: hash of ${f}`).toContain((OWNER as any)[f]);
      }
    }
    expect(await text(page, 'download/ubuntu/', s)).toContain('341,628,878 bytes');
    expect(await text(page, 'download/windows/', s)).toContain('15,556,638 bytes');
    expect(await text(page, 'download/android/', s)).toContain('24,858,225 bytes');
  });

  test('Android page: fingerprint in both forms, both apksigner labels, and "look for the digest"', async ({ page, sites }) => {
    const s = await sites('snap');
    const t = await text(page, 'download/android/', s);
    expect(t).toContain('90:B1:F8:9D:69:CA:9F:26:14:0A:AC:C9:DC:B2:A8:A5:BF:49:43:97:F1:BF:E1:99:A1:26:02:7F:A7:17:D9:36');
    expect(t).toContain('90b1f89d69ca9f26140aacc9dcb2a8a5bf494397f1bfe199a126027fa717d936');
    expect(t).toContain('Signer #1 certificate SHA-256 digest:');
    expect(t).toContain('V2 Signer: certificate SHA-256 digest:');
    expect(t).toContain('Look for the digest, not the label.');
    expect(t).toContain('apksigner verify --print-certs DNDReader-0.3.0-arm64-v8a.apk');
  });

  test('every platform page carries the do-not-run rule for a checksum mismatch', async ({ page, sites }) => {
    const s = await sites('snap');
    for (const p of ['ubuntu', 'windows', 'android']) {
      const t = await text(page, `download/${p}/`, s);
      expect(t).toContain('If the numbers are different');
      expect(t).toContain('Do not run or install the file.');
      expect(t).toContain('open an issue');
    }
  });

  test('per-OS verification commands are the right ones', async ({ page, sites }) => {
    const s = await sites('snap');
    expect(await text(page, 'download/ubuntu/', s)).toContain('sha256sum ~/Downloads/dndreader_0.3.0-1_amd64.deb');
    const w = await text(page, 'download/windows/', s);
    expect(w).toContain('Get-FileHash "$HOME\\Downloads\\DNDReader-0.3.0-setup-x64.exe" -Algorithm SHA256');
    expect(w).toContain('certutil -hashfile');
  });

  test('Windows page explains the warning and never tells anyone to bypass it', async ({ page, sites }) => {
    const s = await sites('snap');
    const t = await text(page, 'download/windows/', s);
    expect(t).toContain('unsigned');
    expect(t).toContain('Whether to run an unsigned installer is your decision');
    expect(t).not.toMatch(/\brun anyway\b|\bmore info\b|\bclick through\b|\bbypass\b|\bget past the warning by\b/i);
  });

  test('older versions: absent with one release', async ({ page, sites }) => {
    const s = await sites('snap');
    expect(await text(page, 'download/', s)).not.toContain('Older versions');
  });
});

test.describe('error and edge states render the designed text', () => {
  for (const name of ['ratelimited', 'netdown', 'servererr']) {
    test(`${name}: builds, degrades honestly, shows no version, size, hash or asset link`, async ({ page, sites }) => {
      const s = await sites(name);
      expect(s.data.status).toBe('unavailable');
      await page.goto(s.url());
      const cta = page.locator('[data-suggest-cta]');
      await expect(cta).toContainText('See the latest release');
      await expect(cta).toHaveAttribute('href', 'https://github.com/thisisankit27/DNDReader/releases/latest');
      await expect(page.locator('.hero__note').first()).toContainText('could not load the current download details');
      for (const p of ['', 'download/', 'download/ubuntu/', 'download/windows/', 'download/android/', 'how-it-works/']) {
        const h = html(s, p);
        expect(h, `${p}: asset links`).not.toContain('/releases/download/');
        expect(h, `${p}: a 64-hex checksum`).not.toMatch(/\b[0-9a-f]{64}\b/);
        expect(h, `${p}: a version number`).not.toMatch(/Version \d+\.\d+\.\d+/);
        expect(h, `${p}: a release file size`).not.toMatch(/\b(342|15\.6|24\.9|19\.9|26\.6) MB\b/);
      }
      await page.goto(s.url('download/windows/'));
      await expect(page.getByText('Download links are temporarily unavailable')).toBeVisible();
      await expect(page.locator('a[data-download]')).toHaveCount(0);
      await expect(page.getByRole('link', { name: /Get the latest release from GitHub/ })).toHaveAttribute('href', 'https://github.com/thisisankit27/DNDReader/releases/latest');
      // the install steps are still useful without data, and still free of invented numbers
      await expect(page.locator('#install')).toBeVisible();
      await page.goto(s.url('download/'));
      await expect(page.locator('.platforms .disabled').first()).toHaveText('Download unavailable right now');
    });
  }

  for (const name of ['empty', 'prerelease']) {
    test(`${name}: says no release is published, and offers no download`, async ({ page, sites }) => {
      const s = await sites(name);
      expect(s.data.status).toBe('no-releases');
      await page.goto(s.url());
      await expect(page.locator('.hero__note').first()).toContainText('No release is published yet.');
      expect(html(s, '')).not.toContain('/releases/download/');
    });
  }

  test('a platform missing from the latest release is said so, never papered over with an old file', async ({ page, sites }) => {
    const s = await sites('nowin');
    await page.goto(s.url('download/windows/'));
    await expect(page.getByText('There is no Windows file in version 0.3.0')).toBeVisible();
    await expect(page.locator('a[data-download]')).toHaveCount(0);
    await page.goto(s.url('download/'));
    await expect(page.locator('#windows .disabled')).toHaveText('Not in this release');
    await expect(page.locator('#ubuntu a[data-download]')).toBeVisible();
    // and the hero does not suggest a Windows file for a Windows visitor
    const ctx = await page.context().browser()!.newContext({ userAgent: UA.windows });
    const p2 = await ctx.newPage();
    await p2.goto(s.url());
    await expect(p2.locator('[data-suggest-cta]')).toContainText('Choose your download');
    await ctx.close();
  });

  test('two releases: the newest is offered, the older is kept for checking, with its hashes', async ({ page, sites }) => {
    const s = await sites('two');
    expect(s.data.releases.map((r: any) => r.version)).toEqual(['0.3.1', '0.3.0']);
    await page.goto(s.url('download/windows/'));
    await expect(page.locator('a[data-primary]')).toHaveAttribute('href', /v0\.3\.1\/DNDReader-0\.3\.1-setup-x64\.exe$/);
    await page.goto(s.url('download/'));
    await expect(page.getByRole('heading', { name: 'Older versions' })).toBeVisible();
    await page.getByText('Version 0.3.0').click();
    await expect(page.getByText(OWNER['DNDReader-0.3.0-setup-x64.exe'])).toBeVisible();
    await expect(page.getByRole('link', { name: 'DNDReader-0.3.0-setup-x64.exe' })).toHaveAttribute('href', /v0\.3\.0\//);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Download DNDReader');
    await expect(page.locator('.page-head .lede')).toContainText('Version 0.3.1');
  });

  test('an unrecognised extra file is ignored everywhere', async ({ page, sites }) => {
    const s = await sites('extra');
    for (const p of ['', 'download/', 'download/ubuntu/', 'download/android/']) expect(html(s, p)).not.toContain('notes.txt');
    expect(s.data.releases[0].assets).toHaveLength(5);
  });

  test('checksum only in the release notes: still shown, still correct', async ({ page, sites }) => {
    const s = await sites('bodysums');
    expect(s.data.releases[0].assets.every((a: any) => a.sha256Source === 'release-notes')).toBe(true);
    expect(await text(page, 'download/windows/', s)).toContain(OWNER['DNDReader-0.3.0-setup-x64.exe']);
  });

  test('no checksum anywhere: the page says so and shows none, rather than inventing one', async ({ page, sites }) => {
    const s = await sites('nosums');
    for (const p of ['ubuntu', 'windows', 'android']) {
      const t = await text(page, `download/${p}/`, s);
      expect(t).toContain('no checksum is published for this file');
      expect(html(s, `download/${p}/`)).not.toMatch(/\b[0-9a-f]{64}\b/);
    }
  });
});
