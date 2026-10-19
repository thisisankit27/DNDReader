import { defineConfig, devices } from '@playwright/test';

// The suite builds every variant of the site it needs (real release snapshot, error fixtures, both base
// paths) in global setup, then serves each from a static server that behaves like GitHub Pages under a
// project path: anything outside the base 404s, so a root-absolute link genuinely fails.
//   PW_ALL_BROWSERS=1  also run Firefox and WebKit (CI does; locally only if they are installed)
//   SKIP_NETWORK=1     skip the tests that talk to github.com (the live asset checks)
//   PW_REUSE_BUILDS=1  reuse .build-out/ from a previous run
const all = !!process.env.PW_ALL_BROWSERS;
export default defineConfig({
  testDir: './tests/e2e',
  globalSetup: './tests/e2e/global-setup.mjs',
  timeout: 90_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  workers: process.env.CI ? 2 : 4,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: { trace: 'retain-on-failure' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] }, testIgnore: /perf\.spec/ },
    // Performance runs alone, after everything else has finished: CPU contention from parallel workers once
    // made a 0 ms blocking time read as 200 ms, so these never share the machine with other tests.
    { name: 'perf', use: { ...devices['Desktop Chrome'] }, testMatch: /perf\.spec/, dependencies: ['chromium'], fullyParallel: false },
    ...(all
      ? [
          { name: 'firefox', use: { ...devices['Desktop Firefox'] }, testIgnore: /perf\.spec/ },
          { name: 'webkit', use: { ...devices['Desktop Safari'] }, testIgnore: /perf\.spec/ },
        ]
      : []),
  ],
});
