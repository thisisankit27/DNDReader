// Download feedback and platform suggestion.
//
// A download button is a plain link to the file. GitHub answers with `Content-Disposition: attachment`, so
// the browser downloads and the page stays put. This script only reacts: it reveals the "started" panel IN
// PLACE (never navigating, which could cancel the request) and says what to expect. It cannot know whether
// the download finished or was blocked, so it never claims either.
//
// Platform detection SUGGESTS. Local only; nothing is sent anywhere.
import { announce } from './announce.js';
import { detectPlatform, archWarning, isDownloadTarget } from '../lib/detect.js';

const NAMES = { ubuntu: 'Ubuntu', windows: 'Windows', android: 'Android', macos: 'macOS', ios: 'iPhone or iPad', chromeos: 'ChromeOS' };

function onDownloadClick(e) {
  const a = e.target.closest('a[data-download]');
  if (!a) return;
  const scope = a.closest('[data-dl]');
  const panel = scope?.querySelector('[data-started]');
  if (!panel) return;
  const file = a.dataset.file;
  const size = a.dataset.size;
  panel.querySelector('[data-started-file]').textContent = file;
  panel.querySelector('[data-started-size]').textContent = size;
  panel.querySelector('[data-started-again]').href = a.href;
  panel.hidden = false;
  announce(`Download started: ${file}, ${size}. Look in your browser's downloads.`);
  const title = panel.querySelector('[data-started-title]');
  if (title) { title.setAttribute('tabindex', '-1'); title.focus(); }
}

async function architecture() {
  try {
    const uad = navigator.userAgentData;
    if (!uad?.getHighEntropyValues) return null;
    return await uad.getHighEntropyValues(['architecture', 'bitness']);
  } catch { return null; }
}

function suggestHero(detected, data) {
  const root = document.querySelector('[data-suggest]');
  if (!root) return;
  const cta = root.querySelector('[data-suggest-cta]');
  const guess = root.querySelector('[data-suggest-guess]');
  const { platform, distroUnsure } = detected;
  if (isDownloadTarget(platform) && data[platform]) {
    const d = data[platform];
    cta.href = d.url;
    cta.dataset.download = '';
    cta.dataset.file = d.filename;
    cta.dataset.size = d.size;
    cta.querySelector('[data-suggest-label]').textContent = `Download for ${NAMES[platform]}`;
    cta.querySelector('[data-suggest-sub]').textContent = `Version ${d.version} · ${d.size}`;
    guess.querySelector('[data-guess-text]').textContent = `Looks like you're on ${NAMES[platform]}. Not right? `;
    guess.hidden = false;
    if (distroUnsure) root.querySelector('[data-distro-note]')?.removeAttribute('hidden');
    const nextLink = root.querySelector('[data-started-next]');
    if (nextLink) nextLink.href = nextLink.dataset.base + platform + '/#install';
  } else if (NAMES[platform]) {
    guess.querySelector('[data-guess-text]').textContent = `DNDReader isn't available for ${NAMES[platform]} yet. It is available for Ubuntu, Windows and Android. `;
    guess.hidden = false;
  }
}

function platformPageNotice(detected) {
  const page = document.querySelector('[data-platform-page]');
  const note = document.querySelector('[data-platform-mismatch]');
  if (!page || !note) return;
  const here = page.dataset.platformPage;
  const { platform } = detected;
  if (platform === 'unknown' || platform === here) return;
  const text = note.querySelector('[data-mismatch-text]');
  if (isDownloadTarget(platform)) {
    text.textContent = `This page is for ${NAMES[here]}. You look like you're on ${NAMES[platform]}. `;
    const link = note.querySelector('[data-mismatch-link]');
    link.href = note.dataset.base + platform + '/';
    link.textContent = `Go to the ${NAMES[platform]} page`;
  } else {
    text.textContent = `You look like you're on ${NAMES[platform]}, and DNDReader isn't available for that yet. `;
    note.querySelector('[data-mismatch-link]').hidden = true;
  }
  note.hidden = false;
}

async function archNotice(detected) {
  const page = document.querySelector('[data-platform-page]');
  if (!page || detected.platform !== page.dataset.platformPage) return;
  const warn = archWarning(await architecture());
  if (!warn) return;
  const el = document.querySelector(`[data-arch-warn="${warn}"]`);
  if (el) el.hidden = false;
}

export function initDownload() {
  document.addEventListener('click', onDownloadClick);
  const detected = detectPlatform(navigator.userAgent, navigator.maxTouchPoints || 0);
  const raw = document.getElementById('dl-data');
  if (raw) {
    try { suggestHero(detected, JSON.parse(raw.textContent)); } catch {}
  }
  platformPageNotice(detected);
  archNotice(detected);
}
