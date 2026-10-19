import { test, expect, PAGES } from './fixtures';

test.describe('navigation', () => {
  test('header and footer links reach the pages they name', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    await expect(page).toHaveTitle(/DNDReader/);
    await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Download' }).click();
    await expect(page).toHaveURL(s.url('download/'));
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Download DNDReader');
    await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'How it works' }).click();
    await expect(page).toHaveURL(s.url('how-it-works/'));
    await page.getByRole('link', { name: 'DNDReader', exact: true }).first().click();
    await expect(page).toHaveURL(s.url());
    // Each platform row leads to its install page.
    for (const p of ['ubuntu', 'windows', 'android']) {
      await page.goto(s.url('download/'));
      await page.locator(`#${p}`).getByRole('link', { name: 'Install steps' }).click();
      await expect(page).toHaveURL(s.url(`download/${p}/`));
    }
  });

  test('the current page is marked in the nav', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/'));
    await expect(page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Download' })).toHaveAttribute('aria-current', 'page');
  });

  test('skip link is the first Tab stop and moves focus to the content', async ({ page, sites }) => {
    const s = await sites('snap');
    for (const p of PAGES) {
      await page.goto(s.url(p));
      await page.keyboard.press('Tab');
      const skip = page.getByRole('link', { name: 'Skip to content' });
      await expect(skip).toBeFocused();
      await expect(skip).toBeInViewport();
      await page.keyboard.press('Enter');
      await expect(page.locator('#main')).toBeFocused();
    }
  });

  test('a missing page is a real 404 with a way back', async ({ page, sites }) => {
    const s = await sites('snap');
    const res = await page.goto(s.url('no-such-page/'));
    expect(res!.status()).toBe(404);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText("That page doesn't exist");
    await expect(page.getByRole('link', { name: 'Download DNDReader' })).toHaveAttribute('href', `${s.base}download/`);
  });

  test('/download/linux/ forwards to the Ubuntu page, under either base path', async ({ page, sites }) => {
    for (const name of ['snap', 'snap-root']) {
      const s = await sites(name);
      await page.goto(s.url('download/linux/'));
      await page.waitForURL(s.url('download/ubuntu/'));
      await expect(page.getByRole('heading', { level: 1 })).toHaveText('DNDReader for Ubuntu');
    }
  });

  test('every platform page names its platform in the h1 and links onward', async ({ page, sites }) => {
    const s = await sites('snap');
    for (const [p, name] of [['ubuntu', 'Ubuntu'], ['windows', 'Windows'], ['android', 'Android']]) {
      await page.goto(s.url(`download/${p}/`));
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(`DNDReader for ${name}`);
      await expect(page.getByRole('link', { name: 'Other platforms' })).toHaveAttribute('href', `${s.base}download/`);
      await expect(page.getByRole('link', { name: /How looking things up works/ })).toHaveAttribute('href', `${s.base}how-it-works/`);
    }
  });
});
