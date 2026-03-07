// assets/js/copy_email.js
// Handles all [data-copy] buttons sitewide.
// No framework. Attach once on DOMContentLoaded.
// Works across page navigations because Phoenix uses full page loads
// for controller-rendered pages.

function initCopyButtons() {
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    // Avoid double-binding on LiveView re-renders
    if (btn.dataset.copyBound) return;
    btn.dataset.copyBound = "true";

    btn.addEventListener("click", async () => {
      const text = btn.dataset.copy;
      if (!text) return;

      try {
        await navigator.clipboard.writeText(text);
        showCopied(btn);
      } catch {
        // Fallback for older browsers / http (non-secure contexts)
        fallbackCopy(text);
        showCopied(btn);
      }
    });
  });
}

function showCopied(btn) {
  const copyIcon  = btn.querySelector(".copy-btn__icon--copy");
  const checkIcon = btn.querySelector(".copy-btn__icon--check");

  btn.classList.add("copy-btn--copied");
  if (copyIcon)  copyIcon.style.display  = "none";
  if (checkIcon) checkIcon.style.display = "";

  setTimeout(() => {
    btn.classList.remove("copy-btn--copied");
    if (copyIcon)  copyIcon.style.display  = "";
    if (checkIcon) checkIcon.style.display = "none";
  }, 2000);
}

function fallbackCopy(text) {
  const el = document.createElement("textarea");
  el.value = text;
  el.style.position = "fixed";
  el.style.opacity  = "0";
  document.body.appendChild(el);
  el.focus();
  el.select();
  document.execCommand("copy");
  document.body.removeChild(el);
}

// Run on initial load
document.addEventListener("DOMContentLoaded", initCopyButtons);

// Re-run after LiveView patches the DOM (labs pages use LiveView)
document.addEventListener("phx:update", initCopyButtons);

export { initCopyButtons };