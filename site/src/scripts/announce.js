// One persistent polite live region (in Layout). Clearing first makes a repeated message announce again.
export function announce(message) {
  const el = document.getElementById('live');
  if (!el) return;
  el.textContent = '';
  setTimeout(() => { el.textContent = message; }, 60);
}
