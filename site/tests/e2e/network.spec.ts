import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test, expect } from './fixtures';

// These talk to github.com. They are the proof that what the pages say is what GitHub serves: every
// download URL resolves to a real attachment of the stated size, and the checksum on the page is the
// SHA-256 of the bytes that actually arrive. SKIP_NETWORK=1 skips them.
test.describe('@network: the download links resolve to real assets', () => {
  test.skip(!!process.env.SKIP_NETWORK, 'SKIP_NETWORK is set');

  test('every asset URL in the live release answers 200 as an attachment, with the stated name and size', async ({ request, sites }) => {
    const s = await sites('live');
    test.skip(s.data.status !== 'ok', `GitHub's API was unavailable for this build (${s.data.error}); the deploy is skipped in that case too`);
    const assets = s.data.releases[0].assets;
    expect(assets.length).toBeGreaterThanOrEqual(1);
    for (const a of assets) {
      const r = await request.fetch(a.url, { method: 'HEAD', maxRedirects: 5, timeout: 60_000 });
      expect(r.status(), a.filename).toBe(200);
      expect(r.headers()['content-disposition'], a.filename).toContain(`attachment; filename=${a.filename}`);
      expect(Number(r.headers()['content-length']), `${a.filename} size`).toBe(a.bytes);
    }
  });

  test('the 342 MB .deb supports ranged requests (so a failed download can resume), without downloading it', async ({ request, sites }) => {
    const s = await sites('live');
    const deb = s.data.releases[0].assets.find((a: any) => a.platform === 'ubuntu');
    const r = await request.fetch(deb.url, { headers: { range: 'bytes=0-1023' }, maxRedirects: 5, timeout: 60_000 });
    expect(r.status()).toBe(206);
    expect((await r.body()).length).toBe(1024);
    expect(r.headers()['content-range']).toMatch(new RegExp(`^bytes 0-1023/${deb.bytes}$`));
    expect(r.headers()['content-disposition']).toContain('attachment');
  });

  for (const platform of ['android', 'windows'] as const) {
    test(`a real click on the live ${platform} page downloads a file whose SHA-256 is the one printed on the page`, async ({ page, sites }) => {
      const s = await sites('live');
      const asset = s.data.releases[0].assets.find((a: any) => a.platform === platform);
      test.skip(!asset?.sha256, 'no published checksum to compare with');
      await page.goto(s.url(`download/${platform}/`));
      const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 120_000 }), page.locator('a[data-primary]').click()]);
      expect(dl.suggestedFilename()).toBe(asset.filename);
      expect(page.url()).toBe(s.url(`download/${platform}/`)); // the real thing also leaves us on our page
      const failure = await dl.failure();
      if (failure) {
        // Chrome applies its own download protection to executables. That is the browser's decision, and the
        // very warning the Windows page describes; record it rather than assert on a browser policy.
        test.info().annotations.push({ type: 'browser', description: `${asset.filename}: the browser ended the download itself (${failure})` });
        test.skip(platform === 'windows', `Chrome ended the .exe download itself: ${failure}`);
      }
      expect(failure).toBeNull();
      const sha = createHash('sha256').update(await readFile((await dl.path())!)).digest('hex');
      expect(sha).toBe(asset.sha256);
      await page.getByText(/Check that the file is the one published/).click();
      await expect(page.getByText(sha).first()).toBeVisible();
      await expect(page.locator('.dlcard [data-started]')).toBeVisible();
    });
  }

  test('the live pages show the live release (not a stale one)', async ({ page, request, sites }) => {
    const s = await sites('live');
    const r = await request.get('https://api.github.com/repos/thisisankit27/DNDReader/releases/latest');
    if (r.status() === 200) expect((await r.json()).tag_name).toBe(s.data.releases[0].tag);
    await page.goto(s.url());
    await expect(page.locator('footer')).toContainText(`Version ${s.data.releases[0].version}`);
  });
});
