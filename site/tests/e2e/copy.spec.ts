import { test, expect } from './fixtures';

const asset = (s: any, id: string) => s.data.releases[0].assets.find((a: any) => a.id === id);

test.describe('copy buttons', () => {
  test('copy the exact text shown, show "Copied", and announce it', async ({ page, context, browserName, sites }) => {
    test.skip(browserName !== 'chromium', 'clipboard-read permission is Chromium-only; the visible/announced behaviour is covered below for all browsers');
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    const s = await sites('snap');
    const a = asset(s, 'ubuntu-amd64');
    await page.goto(s.url('download/ubuntu/'));
    await page.getByText('Check that the file is the one published').click();

    const cases: [string, string][] = [
      ['Copy the SHA-256 for ' + a.filename, a.sha256],
      ['Copy the checksum command', `sha256sum ~/Downloads/${a.filename}`],
      ['Copy the install command', `sudo apt install ./${a.filename}`],
      ['Copy the cd command', 'cd ~/Downloads'],
      ['Copy the uninstall command', 'sudo apt remove dndreader'],
    ];
    for (const [label, expected] of cases) {
      const btn = page.getByRole('button', { name: label });
      await btn.scrollIntoViewIfNeeded();
      await btn.click();
      expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(expected);
      await expect(btn).toHaveText('Copied');
      await expect(btn).toHaveAttribute('data-state', 'copied');
      await expect(page.locator('#live')).toContainText(/^Copied: /);
    }
  });

  test('the visible state and the announcement work in every browser, and reset', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.addInitScript(() => {
      // Pretend the clipboard works so this test does not depend on a browser permission model.
      Object.defineProperty(navigator, 'clipboard', { value: { writeText: async () => {} }, configurable: true });
    });
    await page.goto(s.url('download/ubuntu/'));
    const btn = page.getByRole('button', { name: 'Copy the install command' });
    await btn.click();
    await expect(btn).toHaveText('Copied');
    await expect(page.locator('#live')).toHaveText('Copied: the install command.');
    await expect(btn).toHaveText('Copy', { timeout: 5000 });
    await expect(btn).not.toHaveAttribute('data-state', /.*/);
  });

  test('when the browser refuses, the text is selected and the visitor is told what to do', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'clipboard', { value: { writeText: async () => { throw new Error('denied'); } }, configurable: true });
      document.execCommand = () => false;
    });
    await page.goto(s.url('download/ubuntu/'));
    const btn = page.getByRole('button', { name: 'Copy the install command' });
    await btn.click();
    await expect(btn).toHaveText('Press Ctrl+C');
    await expect(btn).toHaveAttribute('data-state', 'failed');
    await expect(page.locator('#live')).toContainText('press Control and C');
    const selected = await page.evaluate(() => getSelection()!.toString().trim());
    expect(selected).toMatch(/^sudo apt install \.\/dndreader_0\.3\.0-1_amd64\.deb$/);
  });

  test('long commands wrap instead of scrolling sideways, even on a 320 px phone', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.setViewportSize({ width: 320, height: 640 });
    for (const p of ['download/ubuntu/', 'download/windows/', 'download/android/']) {
      await page.goto(s.url(p));
      await page.evaluate(() => document.querySelectorAll('details').forEach((d) => (d.open = true)));
      const overflow = await page.evaluate(() =>
        [...document.querySelectorAll('.code pre')].filter((pre) => pre.scrollWidth > pre.clientWidth + 1).map((pre) => pre.textContent!.slice(0, 40)),
      );
      expect(overflow, `${p}: code blocks that scroll sideways`).toEqual([]);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
  });

  test('Android page copies both forms of the signing fingerprint', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.addInitScript(() => {
      (window as any).__copied = [];
      Object.defineProperty(navigator, 'clipboard', { value: { writeText: async (t: string) => (window as any).__copied.push(t) }, configurable: true });
    });
    await page.goto(s.url('download/android/'));
    await page.getByText('Check that the file is the one published, and signed by this project').click();
    await page.getByRole('button', { name: 'Copy the certificate fingerprint', exact: true }).click();
    await page.getByRole('button', { name: 'Copy the certificate fingerprint without colons' }).click();
    const copied = await page.evaluate(() => (window as any).__copied);
    expect(copied).toEqual([
      '90:B1:F8:9D:69:CA:9F:26:14:0A:AC:C9:DC:B2:A8:A5:BF:49:43:97:F1:BF:E1:99:A1:26:02:7F:A7:17:D9:36',
      '90b1f89d69ca9f26140aacc9dcb2a8a5bf494397f1bfe199a126027fa717d936',
    ]);
  });
});
