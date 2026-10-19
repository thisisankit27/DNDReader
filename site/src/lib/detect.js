// Platform detection SUGGESTS, it never decides. Everything here runs in the visitor's browser and nothing
// is sent anywhere. Honest limits: a browser cannot tell the CPU architecture on Linux, nor the ABI on
// Android, so the UI always offers every option and treats this as a default only.

/**
 * @param {string} ua            navigator.userAgent
 * @param {number} [touchPoints] navigator.maxTouchPoints (iPadOS reports a Mac user agent)
 * @returns {{ platform: 'ubuntu'|'windows'|'android'|'macos'|'ios'|'chromeos'|'unknown', distroUnsure: boolean }}
 *   platform is a DOWNLOAD target when it is ubuntu/windows/android; macos/ios/chromeos mean "recognised,
 *   but there is no build for it"; unknown means "no suggestion".
 */
export function detectPlatform(ua = '', touchPoints = 0) {
  if (!ua || /bot|crawl|spider|slurp|bingpreview|facebookexternalhit/i.test(ua)) return { platform: 'unknown', distroUnsure: false };
  if (/Android/i.test(ua)) return { platform: 'android', distroUnsure: false }; // before Linux: Android UAs say Linux
  if (/iPhone|iPad|iPod/i.test(ua)) return { platform: 'ios', distroUnsure: false };
  if (/Macintosh|Mac OS X/i.test(ua)) return { platform: touchPoints > 1 ? 'ios' : 'macos', distroUnsure: false };
  if (/CrOS/i.test(ua)) return { platform: 'chromeos', distroUnsure: false };
  if (/Windows NT|Win64|Win32|WOW64/i.test(ua)) return { platform: 'windows', distroUnsure: false };
  if (/Linux|X11|Ubuntu/i.test(ua)) return { platform: 'ubuntu', distroUnsure: !/Ubuntu/i.test(ua) };
  return { platform: 'unknown', distroUnsure: false };
}

/**
 * Architecture advice from the high-entropy client hints (Chromium only; Firefox and Safari give nothing,
 * and then we say nothing). Used only to WARN, never to hide a download.
 * @param {{architecture?: string, bitness?: string}|null|undefined} hints
 * @returns {'arm'|'x86-32'|null}
 */
export function archWarning(hints) {
  if (!hints) return null;
  if (hints.architecture === 'arm') return 'arm';
  if (hints.bitness === '32') return 'x86-32';
  return null;
}

export const DOWNLOAD_PLATFORMS = ['ubuntu', 'windows', 'android'];
export const isDownloadTarget = (p) => DOWNLOAD_PLATFORMS.includes(p);
