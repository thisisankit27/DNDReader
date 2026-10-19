// Every build the suite needs. `fixture` is a file in tests/fixtures (null = the real GitHub API).
export const PROJECT_BASE = '/DNDReader';
export const CUSTOM_ORIGIN = 'https://dndreader.example';

export const VARIANTS = {
  snap: { fixture: 'api-live-0.3.0.json', base: PROJECT_BASE }, // the real 0.3.0 data: deterministic
  'snap-root': { fixture: 'api-live-0.3.0.json', base: '/', siteUrl: CUSTOM_ORIGIN }, // the custom-domain config
  live: { fixture: null, base: PROJECT_BASE, network: true },
  two: { fixture: 'api-two-releases-synthetic.json', base: PROJECT_BASE },
  nowin: { fixture: 'api-no-windows-synthetic.json', base: PROJECT_BASE },
  extra: { fixture: 'api-extra-asset-synthetic.json', base: PROJECT_BASE },
  bodysums: { fixture: 'api-body-checksums-only-synthetic.json', base: PROJECT_BASE },
  nosums: { fixture: 'api-no-checksums-synthetic.json', base: PROJECT_BASE },
  ratelimited: { fixture: 'api-rate-limited.json', base: PROJECT_BASE },
  netdown: { fixture: 'api-network-down.json', base: PROJECT_BASE },
  servererr: { fixture: 'api-server-error.json', base: PROJECT_BASE },
  empty: { fixture: 'api-empty.json', base: PROJECT_BASE },
  prerelease: { fixture: 'api-prerelease-only-synthetic.json', base: PROJECT_BASE },
};
