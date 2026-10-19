export function lum([r, g, b]: number[]) {
  const f = (v: number) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
export function ratio(a: number[], b: number[]) {
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}
/** "rgb(20, 35, 58)" or "#14233a" -> [20,35,58] */
export function rgb(c: string): number[] {
  c = c.trim();
  if (c.startsWith('#')) { const h = c.slice(1); return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)); }
  return (c.match(/[\d.]+/g) ?? []).slice(0, 3).map(Number);
}
