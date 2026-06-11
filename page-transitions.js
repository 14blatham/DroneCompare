// Fade in on load, fade out before navigation
(function () {
  const style = document.createElement('style');
  style.textContent = `
    body { animation: pageFadeIn 0.25s ease-out; }
    @keyframes pageFadeIn  { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
    body.page-leaving { animation: pageFadeOut 0.2s ease-in forwards; pointer-events: none; }
    @keyframes pageFadeOut { from { opacity: 1; transform: translateY(0); } to { opacity: 0; transform: translateY(-4px); } }
  `;
  document.head.appendChild(style);

  document.addEventListener('click', function (e) {
    const link = e.target.closest('a[href]');
    if (!link) return;
    const href = link.getAttribute('href');
    if (!href || href === '#' || href.startsWith('http') || href.startsWith('mailto:') || href.startsWith('tel:')) return;
    e.preventDefault();
    document.body.classList.add('page-leaving');
    setTimeout(function () { window.location.href = href; }, 200);
  });

  document.querySelector('[data-icon="menu"]')?.addEventListener('click', () => {
    document.querySelector('nav ul')?.classList.toggle('hidden');
  });
})();
