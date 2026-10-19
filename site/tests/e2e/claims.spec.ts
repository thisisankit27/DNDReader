import { test, expect, PAGES } from './fixtures';

// The claims guard. The brief's rules, as tests over everything a visitor can read (visible text, closed
// disclosures, titles and meta descriptions): no superlatives or world-firsts, no unqualified
// privacy/security/free/offline claims, no invented social proof, and every documented limitation present.
const FORBIDDEN: [RegExp, string][] = [
  [/\bfirst\b/i, 'a "first" claim'],
  [/\bonly (PDF )?reader\b/i, '"only reader"'],
  [/\bin the world\b|\bworld'?s?\b|\bworldwide\b/i, 'a world claim'],
  [/\b(the )?best\b/i, '"best"'],
  [/\bfastest\b|\bblazing\b|\blightning\b/i, 'a speed superlative'],
  [/\bnumber one\b|(?<!Signer )#1\b|\bleading\b|\baward\b|\bunrivall?ed\b|\bunmatched\b|\brevolutionary\b/i, 'a superlative'],
  [/AI-powered|AI-driven|powered by AI|AI assistant that|smart answers/i, 'an AI-product claim'],
  [/\bfree\b(?! disk space)/i, 'an unqualified "free"'],
  [/\bsecure\b|\bsecurely\b/i, 'an unqualified "secure"'],
  [/\boffline\b/i, '"offline"'],
  [/\bprivate\b(?! (copy|copies|storage))/i, 'an unqualified "private"'],
  [/\bprivately\b|\banonymous\b|\buntraceable\b/i, 'a privacy claim'],
  [/testimonial|trusted by|loved by|used by|users worldwide|\d[\d,.]*\s*(k|m|\+)?\s*(users|downloads|stars|installs)\b/i, 'invented social proof'],
  [/\b(uptime|99\.\d+%)\b/i, 'an uptime figure'],
  [/\bseamless(ly)?\b|\bpowerful\b|\bcutting-edge\b|\bnext-gen/i, 'marketing filler'],
];

test.describe('claims guard', () => {
  test('nothing a visitor can read makes a forbidden claim', async ({ page, sites }) => {
    const s = await sites('snap');
    const hits: string[] = [];
    for (const p of [...PAGES, 'missing/']) {
      await page.goto(s.url(p));
      const all: string[] = await page.evaluate(() => [
        document.title,
        document.querySelector('meta[name=description]')?.getAttribute('content') ?? '',
        document.querySelector('meta[property="og:description"]')?.getAttribute('content') ?? '',
        document.body.textContent!.replace(/\s+/g, ' '),
      ]);
      const text = all.join(' || ');
      for (const [re, what] of FORBIDDEN) {
        const m = re.exec(text);
        if (m) hits.push(`${p || 'home'}: ${what}: ...${text.slice(Math.max(0, m.index - 40), m.index + 60)}...`);
      }
    }
    expect(hits).toEqual([]);
  });

  const HOME = [
    [/AI Overview sometimes appears and often doesn't\. DNDReader does not promise one/, 'AI Overview not guaranteed'],
    [/can't sign in to Google in the panel/, 'no Google sign-in'],
    [/consent screen can appear in the panel, and occasionally a CAPTCHA/, 'consent screens and CAPTCHA'],
    [/Looking something up needs an internet connection\. Reading a PDF does not/, 'the panel needs a network'],
    [/Text-based PDFs only\./, 'text-based PDFs only'],
    [/there is no OCR/, 'no OCR'],
    [/held in memory only and discarded when DNDReader quits/, 'Ubuntu privacy statement'],
    [/cleared and deleted when you quit/, 'Windows privacy statement'],
    [/During a session that data is on disk/, 'Windows: it is on disk during a session'],
    [/deleted the next time the app starts\. It is not gone the moment you swipe the app away/, 'Android privacy statement'],
    [/(sent to Google as a search|as a Google search, when you choose Find meaning)/, 'what leaves the device'],
    [/Your PDF is never uploaded/, 'PDF never uploaded'],
    [/no telemetry,( no)? analytics,? (or|no) crash reporting/i, 'no telemetry'],
    [/Apache-2\.0/, 'the licence'],
    [/one published release so far/, 'one release, stated plainly'],
    [/It is not a company and has no user numbers to quote/, 'no invented metrics'],
  ] as const;

  test('the home page carries every documented limitation and the three separate privacy statements', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    for (const [re, what] of HOME) expect(t, what).toMatch(re);
    // per-platform privacy must stay three statements, not one reassuring sentence
    expect(await page.locator('.privacy > div').count()).toBe(3);
    expect(await page.locator('.privacy dt').allTextContents()).toEqual(['Ubuntu', 'Windows', 'Android']);
  });

  test('how-it-works repeats them and adds the unresolved Google-terms question', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('how-it-works/'));
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    for (const [re, what] of HOME.filter(([, w]) => !/licence|one release|metrics/.test(w))) expect(t, what).toMatch(re);
    expect(t).toMatch(/Whether Google's terms permit loading Search inside another app's panel has not been established/);
    expect(t).toMatch(/DNDReader never reads, scrapes or automates the results page/);
    expect(t).toMatch(/not an AI assistant and has none of its own/);
  });

  test('Android: private copy, memory against target, one permission', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/android/'));
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    expect(t).toMatch(/copies each document into its own private storage/);
    expect(t).toMatch(/Changes to the original don't appear until you open or share the file again/);
    expect(t).toMatch(/about 517 MB/);
    expect(t).toMatch(/300 MB target we set and missed/);
    expect(t).toMatch(/asks for one permission, Internet/);
    expect(t).toMatch(/Android 8\.0 or newer/);
    expect(t).toMatch(/Tested on one phone \(Moto G60, Android 12\)/);
    expect(t).toMatch(/Not yet tested: Android 13 or newer on a real phone, TalkBack/);
    expect(t).toMatch(/never been run on a device/);
  });

  test('Android does not coach anyone past a protection', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/android/'));
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    expect(t).not.toMatch(/\b(tap|press|click|choose|select)\s+(["“]?(keep|install anyway|allow|ok|more details|install without scanning)\b)/i);
    expect(t).not.toMatch(/disable play protect|turn off play protect|ignore the warning|dismiss/i);
    expect(t).toMatch(/If it blocks the installation, stop there and don't work around it/);
    expect(t).toMatch(/Allow it only if you are happy with where the file came from/);
  });

  test('Windows: unsigned, SmartScreen explained, the decision left to the reader, requirement stated', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/windows/'));
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    expect(t).toMatch(/isn't signed with a code-signing certificate/);
    expect(t).toMatch(/Windows 10 \(version 1809\) or newer/);
    expect(t).toMatch(/This page doesn't tell you how to get past the warning/);
    expect(t).toMatch(/Tested on one Windows 10 22H2 computer/);
    expect(t).toMatch(/Not yet tested: Windows 11/);
  });

  test('Ubuntu: names the release it targets, and explains the size', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url('download/ubuntu/'));
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    expect(t).toMatch(/Ubuntu 26\.04/);
    expect(t).toMatch(/Other Ubuntu releases and other Linux distributions have not been tested/);
    expect(t).toMatch(/dependencies were taken from a 26\.04 machine/);
    expect(t).toMatch(/Linux has no built-in web view/);
    expect(t).toMatch(/There is no automatic update/);
    expect(t).toMatch(/does not fall back to an unsandboxed browser/);
  });

  test('the app is described as open source with no overclaiming of platforms', async ({ page, sites }) => {
    const s = await sites('snap');
    await page.goto(s.url());
    const t = await page.evaluate(() => document.body.textContent!.replace(/\s+/g, ' '));
    expect(t).not.toMatch(/macOS|iOS|iPhone|iPad/); // nothing implies a build that does not exist
    expect(t).toMatch(/Ubuntu 26\.04/);
  });
});
