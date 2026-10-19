import { test, expect, UA, stubDownloads } from './fixtures';

// Downloads are stubbed with the same headers GitHub sends (verified separately, against GitHub, in
// network.spec.ts): attachment + filename. What is tested here is the PAGE: that clicking starts the file
// without navigating, and that the page then says the truth.
const asset = (s: any, id: string) => s.data.releases[0].assets.find((a: any) => a.id === id);

test.describe('download starts at once, and the visitor stays on the page', () => {
  test('hero button: starts the file, does not navigate, shows the started panel', async ({ browser, sites }) => {
    const s = await sites('snap');
    const ctx = await browser.newContext({ userAgent: UA.windows });
    const page = await ctx.newPage();
    await stubDownloads(page);
    await page.goto(s.url());
    const a = asset(s, 'windows-x64');
    const [dl] = await Promise.all([page.waitForEvent('download'), page.locator('[data-suggest-cta]').click()]);
    expect(dl.suggestedFilename()).toBe(a.filename);
    expect(page.url()).toBe(s.url()); // never left our page
    const panel = page.locator('[data-suggest] [data-started]');
    await expect(panel).toBeVisible();
    await expect(panel).toContainText(a.filename);
    await expect(panel).toContainText('15.6 MB');
    await expect(panel.locator('[data-started-title]')).toBeFocused();
    await expect(page.locator('#live')).toContainText(`Download started: ${a.filename}`);
    await expect(panel.getByRole('link', { name: 'Download it again' })).toHaveAttribute('href', a.url);
    await expect(panel.locator('[data-started-next]')).toHaveAttribute('href', `${s.base}download/windows/#install`);
    // It never claims the download FINISHED: the page cannot know.
    await expect(panel).not.toContainText(/complete|finished|done/i);
    await ctx.close();
  });

  for (const [p, id] of [['ubuntu', 'ubuntu-amd64'], ['windows', 'windows-x64'], ['android', 'android-arm64-v8a']] as const) {
    test(`${p} page: main button downloads the right file in place`, async ({ page, sites }) => {
      const s = await sites('snap');
      await stubDownloads(page);
      await page.goto(s.url(`download/${p}/`));
      const a = asset(s, id);
      const btn = page.locator('a[data-primary]');
      await expect(btn).toHaveAttribute('href', a.url);
      await expect(btn).toContainText(a.bytes > 100e6 ? '342 MB' : /\d MB/);
      const [dl] = await Promise.all([page.waitForEvent('download'), btn.click()]);
      expect(dl.suggestedFilename()).toBe(a.filename);
      expect(page.url()).toBe(s.url(`download/${p}/`));
      const panel = page.locator('.dlcard [data-started]');
      await expect(panel).toBeVisible();
      await expect(panel).toContainText(a.filename);
      await expect(panel.locator('[data-started-next]')).toHaveAttribute('href', '#install');
    });
  }

  test('keyboard: Enter on the focused button starts the download', async ({ page, sites }) => {
    const s = await sites('snap');
    await stubDownloads(page);
    await page.goto(s.url('download/windows/'));
    await page.locator('a[data-primary]').focus();
    const [dl] = await Promise.all([page.waitForEvent('download'), page.keyboard.press('Enter')]);
    expect(dl.suggestedFilename()).toBe(asset(s, 'windows-x64').filename);
  });

  test('Android alternative files download too, and the panel names the one you chose', async ({ page, sites }) => {
    const s = await sites('snap');
    await stubDownloads(page);
    await page.goto(s.url('download/android/'));
    await page.locator('#other-files summary').click();
    const [dl] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: /x86_64 file/ }).click()]);
    expect(dl.suggestedFilename()).toBe(asset(s, 'android-x86_64').filename);
    await expect(page.locator('.dlcard [data-started]')).toContainText(asset(s, 'android-x86_64').filename);
  });

  test('refresh returns to idle: no panel, and no second download', async ({ page, sites }) => {
    const s = await sites('snap');
    await stubDownloads(page);
    await page.goto(s.url('download/ubuntu/'));
    await Promise.all([page.waitForEvent('download'), page.locator('a[data-primary]').click()]);
    await expect(page.locator('.dlcard [data-started]')).toBeVisible();
    let downloads = 0;
    page.on('download', () => downloads++);
    await page.reload();
    await page.waitForTimeout(800);
    await expect(page.locator('.dlcard [data-started]')).toBeHidden();
    expect(downloads).toBe(0);
    await expect(page.locator('#install')).toBeVisible(); // the steps are still right there
  });

  test('chooser rows each start their own download and offer their own next step', async ({ page, sites }) => {
    const s = await sites('snap');
    await stubDownloads(page);
    await page.goto(s.url('download/'));
    for (const [p, id] of [['ubuntu', 'ubuntu-amd64'], ['windows', 'windows-x64'], ['android', 'android-arm64-v8a']] as const) {
      const row = page.locator(`#${p}`);
      const [dl] = await Promise.all([page.waitForEvent('download'), row.locator('a[data-download]').click()]);
      expect(dl.suggestedFilename()).toBe(asset(s, id).filename);
      await expect(row.locator('[data-started]')).toBeVisible();
      await expect(row.locator('[data-started-next]')).toHaveAttribute('href', `${s.base}download/${p}/#install`);
    }
    expect(page.url()).toBe(s.url('download/'));
  });

  test('the Ubuntu size is stated up front and explained, before any click', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/ubuntu/'));
    const card = page.locator('.dlcard');
    await expect(card).toContainText('342 MB');
    await expect(card).toContainText('341,628,878 bytes');
    await expect(card).toContainText('Why is it so large?');
    await expect(card).toContainText('1.5 GB');
    await expect(page.locator('.dlcard [data-started]')).toBeHidden();
  });
});
