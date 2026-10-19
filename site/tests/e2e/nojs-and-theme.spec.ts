import { test, expect, UA } from './fixtures';

test.describe('without JavaScript the site still works', () => {
  test.use({ javaScriptEnabled: false, userAgent: UA.windows });

  test('home: the button leads to the chooser, the reader illustration is shown open, no dead controls', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    await expect(page.locator('[data-suggest-cta]')).toHaveAttribute('href', `${s.base}download/`);
    await expect(page.locator('[data-reader-panel]')).toBeVisible();
    await expect(page.locator('[data-reader-open]')).toBeHidden();
    await expect(page.locator('[data-theme-select]')).toBeHidden();
  });

  test('chooser: every download is a plain link to the real file', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/'));
    for (const a of s.data.releases[0].assets.filter((x: any) => ['ubuntu-amd64', 'windows-x64', 'android-arm64-v8a'].includes(x.id))) {
      await expect(page.locator(`a[href="${a.url}"]`)).toBeVisible();
    }
  });

  test('platform pages: disclosures open natively, copy buttons are absent, commands are selectable text', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/ubuntu/'));
    await expect(page.locator('button.copy').first()).toBeHidden();
    await page.getByText('Check that the file is the one published').click();
    await expect(page.getByText(s.data.releases[0].assets.find((a: any) => a.id === 'ubuntu-amd64').sha256)).toBeVisible();
    await expect(page.getByText('sudo apt install ./dndreader_0.3.0-1_amd64.deb')).toBeVisible();
    await expect(page.locator('.dlcard [data-started]')).toBeHidden();
  });
});

test.describe('theme', () => {
  test('dark follows the system, light follows it too, and an explicit choice wins and persists', async ({ page, sites }) => {
    const s = await sites('snap');
    const bg = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.goto(s.url());
    expect(await bg()).toBe('rgb(14, 23, 38)'); // #0e1726
    await page.emulateMedia({ colorScheme: 'light' });
    expect(await bg()).toBe('rgb(246, 248, 251)'); // #f6f8fb

    const select = page.getByLabel('Colour theme');
    await expect(select).toBeVisible();
    await select.selectOption('dark');
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    expect(await bg()).toBe('rgb(14, 23, 38)'); // forced dark although the system is light
    expect(await page.evaluate(() => localStorage.getItem('dnd-theme'))).toBe('dark');

    await page.reload();
    await expect(select).toHaveValue('dark');
    expect(await bg()).toBe('rgb(14, 23, 38)');

    await select.selectOption('system');
    await expect(page.locator('html')).not.toHaveAttribute('data-theme', /.*/);
    expect(await page.evaluate(() => localStorage.getItem('dnd-theme'))).toBeNull();
    expect(await bg()).toBe('rgb(246, 248, 251)');
  });

  test('the saved choice is applied before first paint (no flash of the wrong theme)', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.addInitScript(() => {
      localStorage.setItem('dnd-theme', 'dark');
      document.addEventListener('DOMContentLoaded', () => ((window as any).__atDCL = document.documentElement.dataset.theme));
      new MutationObserver(() => {}).observe(document, { childList: true });
    });
    await page.emulateMedia({ colorScheme: 'light' });
    await page.goto(s.url());
    expect(await page.evaluate(() => (window as any).__atDCL)).toBe('dark');
    // and the theme control itself is revealed only once it works
    await expect(page.getByLabel('Colour theme')).toBeVisible();
  });

  test('a throwing localStorage does not break the page', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.addInitScript(() => {
      Object.defineProperty(window, 'localStorage', { get() { throw new Error('blocked'); } });
    });
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto(s.url());
    await page.getByLabel('Colour theme').selectOption('dark').catch(() => {});
    expect(errors).toEqual([]);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  });

  test('both dark token blocks (system preference and explicit choice) are identical', async ({ page, sites }) => {
    const s = await sites('snap');
    const tokens = () => page.evaluate(() => {
      const cs = getComputedStyle(document.documentElement);
      return Object.fromEntries(['--page','--surface','--ink','--body','--muted','--link','--accent','--on-accent','--accent-text','--primary','--primary-hover','--on-primary','--rule','--control','--code-bg','--focus','--on-hl','--paper','--ok','--ok-tint','--warn','--warn-tint','--danger','--danger-tint','--shadow','--grid','--glow-1','--glow-2'].map((k) => [k, cs.getPropertyValue(k).trim()]));
    });
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.goto(s.url());
    const viaSystem = await tokens();
    await page.emulateMedia({ colorScheme: 'light' });
    await page.evaluate(() => (document.documentElement.dataset.theme = 'dark'));
    const viaChoice = await tokens();
    expect(viaChoice).toEqual(viaSystem);
  });
});
