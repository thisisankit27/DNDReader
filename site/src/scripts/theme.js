// System / Light / Dark. The choice is applied before first paint by the inline script in Layout;
// this only wires the control. Storage can throw (private windows), so every access is guarded.
const KEY = 'dnd-theme';

export function initTheme() {
  const select = document.querySelector('[data-theme-select]');
  if (!select) return;
  let saved = '';
  try { saved = localStorage.getItem(KEY) || ''; } catch {}
  select.value = saved === 'light' || saved === 'dark' ? saved : 'system';
  select.closest('.theme')?.removeAttribute('hidden');
  select.addEventListener('change', () => {
    const v = select.value;
    if (v === 'light' || v === 'dark') document.documentElement.dataset.theme = v;
    else delete document.documentElement.dataset.theme;
    try { v === 'system' ? localStorage.removeItem(KEY) : localStorage.setItem(KEY, v); } catch {}
  });
}
