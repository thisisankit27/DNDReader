// One place decides how a byte count is written, so a size can never be worded two ways.
// Decimal units (1 MB = 1,000,000 bytes) because that is what browsers show in the download bar.

/** 341628878 -> "342 MB", 24858225 -> "24.9 MB", 15556638 -> "15.6 MB". */
export function formatSize(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) return '';
  if (bytes < 1_000_000) return `${Math.round(bytes / 1000)} KB`;
  const mb = bytes / 1_000_000;
  return mb >= 100 ? `${Math.round(mb)} MB` : `${mb.toFixed(1)} MB`;
}

/** 341628878 -> "341,628,878 bytes". */
export function formatBytes(bytes) {
  return `${new Intl.NumberFormat('en-US').format(bytes)} bytes`;
}

/** "2026-10-19T11:14:59Z" -> "19 October 2026" (UTC, so the build machine's zone never changes it). */
export function formatDate(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }).format(d);
}
