// The hero illustration: select, "Find meaning", a panel opens, close it, you are still where you were.
// Operable by keyboard: the pill is a button, Escape closes, focus returns to the pill.
const root = document.querySelector('[data-reader]');
if (root) {
  const pill = root.querySelector('[data-reader-open]');
  const panel = root.querySelector('[data-reader-panel]');
  const close = root.querySelector('[data-reader-close]');
  const title = root.querySelector('[data-reader-title]');
  const open = () => { root.dataset.open = ''; pill.setAttribute('aria-expanded', 'true'); title.focus(); };
  const shut = () => { delete root.dataset.open; pill.setAttribute('aria-expanded', 'false'); pill.focus(); };
  pill.addEventListener('click', () => (root.hasAttribute('data-open') ? shut() : open()));
  close.addEventListener('click', shut);
  root.addEventListener('keydown', (e) => { if (e.key === 'Escape' && root.hasAttribute('data-open')) { e.stopPropagation(); shut(); } });
  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'e' && root.contains(document.activeElement)) { e.preventDefault(); open(); }
  });
}
