// Scroll entry for the content blocks. The .js class gates the hidden state in
// CSS, so with this file blocked or broken the page is simply all visible.
document.documentElement.classList.add('js');

const items = [...document.querySelectorAll('.reveal')];

// Siblings inside one group cascade. The index resets per group, so a section
// far down the page never inherits a long delay from the one above it.
document
  .querySelectorAll('.hero-copy, .bento, .presets, .settings-grid, .dl, .faq')
  .forEach((group) => {
    [...group.children].forEach((child, index) => {
      if (child.classList.contains('reveal')) child.style.setProperty('--i', index);
    });
  });

const pending = new Set(items);
const show = (el) => {
  el.classList.add('in');
  pending.delete(el);
};

if (!window.IntersectionObserver) {
  items.forEach(show);
} else {
  // The observer's bottom rootMargin holds an element back until it is a little
  // way into the viewport. On a very tall window the last block on the page can
  // sit inside that dead zone at full scroll and never be released, so a plain
  // "is it on screen" pass runs alongside it and wins whenever it disagrees.
  const sweep = () => {
    pending.forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.top < window.innerHeight && r.bottom > 0) show(el);
    });
    if (!pending.size) {
      removeEventListener('scroll', sweep);
      removeEventListener('resize', sweep);
    }
  };

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        show(entry.target);
        observer.unobserve(entry.target);
      });
    },
    { rootMargin: '0px 0px -10% 0px', threshold: 0.05 },
  );

  // Anything already on screen is released on the next frame rather than by the
  // observer: the first screen must not depend on a callback that a prerenderer
  // or a throttled tab might never deliver.
  const above = items.filter((el) => el.getBoundingClientRect().top < window.innerHeight);
  requestAnimationFrame(() => above.forEach(show));
  items.filter((el) => !above.includes(el)).forEach((el) => observer.observe(el));

  addEventListener('scroll', sweep, { passive: true });
  addEventListener('resize', sweep, { passive: true });
}
