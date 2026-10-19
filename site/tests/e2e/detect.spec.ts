import { test, expect, UA } from './fixtures';

const file = (s: any, id: string) => s.data.releases[0].assets.find((a: any) => a.id === id);

test.describe('platform suggestion: suggests, never decides', () => {
  const cases: [string, string, string, string | null][] = [
    ['Windows Chrome', UA.windows, 'Download for Windows', 'windows-x64'],
    ['Windows Firefox', UA.windowsFirefox, 'Download for Windows', 'windows-x64'],
    ['Android Chrome', UA.android, 'Download for Android', 'android-arm64-v8a'],
    ['Ubuntu Firefox', UA.ubuntu, 'Download for Ubuntu', 'ubuntu-amd64'],
    ['Linux, distro unknown', UA.linux, 'Download for Ubuntu', 'ubuntu-amd64'],
  ];
  for (const [name, ua, label, id] of cases) {
    test(`${name}: hero becomes a direct download for the suggested platform`, async ({ browser, sites }) => {
      const s = await sites('snap');
      const ctx = await browser.newContext({ userAgent: ua });
      const page = await ctx.newPage();
      await page.goto(s.url());
      const cta = page.locator('[data-suggest-cta]');
      await expect(cta).toContainText(label);
      const a = file(s, id!);
      await expect(cta).toHaveAttribute('href', a.url);
      await expect(cta).toContainText(a.bytes > 100e6 ? '342 MB' : /MB/);
      await expect(page.locator('[data-suggest-guess]')).toContainText("Not right?");
      await expect(page.getByRole('link', { name: 'Other downloads' })).toHaveAttribute('href', `${s.base}download/`);
      await ctx.close();
    });
  }

  test('Android defaults to arm64-v8a, and the other files stay one click away', async ({ browser, sites }) => {
    const s = await sites('snap');
    const ctx = await browser.newContext({ userAgent: UA.android });
    const page = await ctx.newPage();
    await page.goto(s.url('download/android/'));
    await expect(page.locator('a[data-primary]')).toHaveAttribute('href', file(s, 'android-arm64-v8a').url);
    await page.locator('#other-files summary').click();
    await expect(page.getByRole('link', { name: /armeabi-v7a file/ })).toHaveAttribute('href', file(s, 'android-armeabi-v7a').url);
    await expect(page.getByRole('link', { name: /x86_64 file/ })).toHaveAttribute('href', file(s, 'android-x86_64').url);
    await ctx.close();
  });

  test('a Linux that does not say Ubuntu gets the honest caveat; one that does, does not', async ({ browser, sites }) => {
    const s = await sites('snap');
    for (const [ua, shown] of [[UA.linux, true], [UA.ubuntu, false]] as const) {
      const ctx = await browser.newContext({ userAgent: ua });
      const page = await ctx.newPage();
      await page.goto(s.url());
      await expect(page.locator('[data-distro-note]')).toBeVisible({ visible: shown });
      await ctx.close();
    }
  });

  test('macOS, iPhone and ChromeOS get "not available yet", with no download invented', async ({ browser, sites }) => {
    const s = await sites('snap');
    for (const [ua, name] of [[UA.mac, 'macOS'], [UA.iphone, 'iPhone or iPad'], [UA.chromeos, 'ChromeOS']] as const) {
      const ctx = await browser.newContext({ userAgent: ua, hasTouch: name !== 'macOS' && name !== 'ChromeOS' });
      const page = await ctx.newPage();
      await page.goto(s.url());
      await expect(page.locator('[data-suggest-guess]')).toContainText(`isn't available for ${name} yet`);
      await expect(page.locator('[data-suggest-cta]')).toHaveAttribute('href', `${s.base}download/`);
      await expect(page.locator('[data-suggest-cta]')).not.toHaveAttribute('data-download', /.*/);
      await ctx.close();
    }
  });

  test('a crawler or unknown browser gets no suggestion at all', async ({ browser, sites }) => {
    const s = await sites('snap');
    for (const ua of ['Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)', 'SomeBrowser/1.0 (PlayStation 5)']) {
      const ctx = await browser.newContext({ userAgent: ua });
      const page = await ctx.newPage();
      await page.goto(s.url());
      await expect(page.locator('[data-suggest-guess]')).toBeHidden();
      await expect(page.locator('[data-suggest-cta]')).toContainText('Choose your download');
      await ctx.close();
    }
  });

  test('on the chooser, "Other downloads" jumps to the full list, which lists every platform equally', async ({ browser, sites }) => {
    const s = await sites('snap');
    const ctx = await browser.newContext({ userAgent: UA.windows });
    const page = await ctx.newPage();
    await page.goto(s.url('download/'));
    await expect(page.getByRole('link', { name: 'Other downloads' })).toHaveAttribute('href', '#all-platforms');
    for (const p of ['ubuntu', 'windows', 'android']) await expect(page.locator(`#${p} a[data-download]`)).toBeVisible();
    await ctx.close();
  });

  test('platform pages say so when you look like a different platform', async ({ browser, sites }) => {
    const s = await sites('snap');
    const ctx = await browser.newContext({ userAgent: UA.windows });
    const page = await ctx.newPage();
    await page.goto(s.url('download/android/'));
    const note = page.locator('[data-platform-mismatch]');
    await expect(note).toBeVisible();
    await expect(note).toContainText("This page is for Android. You look like you're on Windows.");
    await expect(note.getByRole('link')).toHaveAttribute('href', `${s.base}download/windows/`);
    await page.goto(s.url('download/windows/'));
    await expect(page.locator('[data-platform-mismatch]')).toBeHidden();
    await ctx.close();
    const ctx2 = await browser.newContext({ userAgent: UA.mac });
    const p2 = await ctx2.newPage();
    await p2.goto(s.url('download/ubuntu/'));
    await expect(p2.locator('[data-platform-mismatch]')).toContainText("isn't available for that yet");
    await ctx2.close();
  });

  test('architecture hints only ever WARN, and only on the matching platform page', async ({ browser, sites }) => {
    const s = await sites('snap');
    const hints = (architecture: string, bitness: string) => `
      Object.defineProperty(navigator, 'userAgentData', { value: { getHighEntropyValues: async () => ({ architecture: '${architecture}', bitness: '${bitness}' }) } });`;
    const run = async (ua: string, init: string, path: string) => {
      const ctx = await browser.newContext({ userAgent: ua });
      await ctx.addInitScript(init);
      const page = await ctx.newPage();
      await page.goto(s.url(path));
      await page.waitForTimeout(300);
      return { page, ctx };
    };
    let r = await run(UA.windows, hints('arm', '64'), 'download/windows/');
    await expect(r.page.locator('[data-arch-warn="arm"]')).toBeVisible();
    await expect(r.page.locator('a[data-primary]')).toBeVisible(); // the download is still offered
    await r.ctx.close();
    r = await run(UA.windows, hints('x86', '32'), 'download/windows/');
    await expect(r.page.locator('[data-arch-warn="x86-32"]')).toBeVisible();
    await r.ctx.close();
    r = await run(UA.windows, hints('x86', '64'), 'download/windows/');
    await expect(r.page.locator('[data-arch-warn]')).toHaveCount(2);
    await expect(r.page.locator('[data-arch-warn="arm"]')).toBeHidden();
    await r.ctx.close();
    r = await run(UA.mac, hints('arm', '64'), 'download/windows/'); // an ARM Mac reading the Windows page
    await expect(r.page.locator('[data-arch-warn="arm"]')).toBeHidden();
    await r.ctx.close();
    r = await run(UA.ubuntu, hints('arm', '64'), 'download/ubuntu/');
    await expect(r.page.locator('[data-arch-warn="arm"]')).toBeVisible();
    await r.ctx.close();
  });
});
