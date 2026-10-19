// Copy buttons. They are hidden until this runs, so without JavaScript there is no dead control and the
// command is still selectable text. The result is visible on the button AND announced.
import { announce } from './announce.js';

function selectText(node) {
  const range = document.createRange();
  range.selectNodeContents(node);
  const sel = getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}

async function copyText(text, source) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Clipboard API refused or unavailable (insecure context, permissions). Fall back, then give up honestly.
    try {
      selectText(source);
      const ok = document.execCommand('copy');
      if (ok) return true;
    } catch {}
    selectText(source);
    return false;
  }
}

export function initCopy() {
  for (const btn of document.querySelectorAll('button[data-copy]')) {
    btn.hidden = false;
    const idle = btn.textContent.trim() || 'Copy';
    let timer;
    btn.addEventListener('click', async () => {
      const source = document.getElementById(btn.dataset.copy)?.querySelector('code') ?? btn;
      const text = source.textContent.trim();
      const what = btn.dataset.what || 'text';
      const ok = await copyText(text, source);
      clearTimeout(timer);
      btn.dataset.state = ok ? 'copied' : 'failed';
      btn.textContent = ok ? 'Copied' : 'Press Ctrl+C';
      announce(ok ? `Copied: ${what}.` : `Could not copy automatically. ${what} is selected: press Control and C to copy it.`);
      timer = setTimeout(() => { btn.textContent = idle; delete btn.dataset.state; }, ok ? 2500 : 6000);
    });
  }
}
