// The app-icon stickers by the front page's hero: each is a button that sets the site's color theme through
// window.blygletLook (assets/switcher.js), so the Color menu, the nav and hero icons and the appearance
// button all follow, and a choice made in the menu moves the pressed sticker. Six icons are app themes
// (Paper and Ink are Pencil blue, light and dark); the other six take the nearest theme, and the line under
// the stickers says so. Without JavaScript the stickers show and do nothing.
(function () {
  'use strict';
  var sheet = document.querySelector('.sticker-sheet');
  var status = document.querySelector('.sticker-status');
  if (!sheet || !status || !window.blygletLook) return;

  var KEY = 'blyglet-site-icon';
  var CANONICAL = { blue: 'pencil-blue', pink: 'piglet-pink', moss: 'moss', butter: 'butter' };
  var THEMES = { blue: 'Pencil blue', pink: 'Piglet pink', moss: 'Moss', butter: 'Butter' };
  var stickers = Array.prototype.slice.call(sheet.querySelectorAll('.sticker'));

  function fits(sticker, look) {
    return sticker.dataset.palette === look.palette && (!sticker.dataset.mode || sticker.dataset.mode === look.mode);
  }

  // Pressed: the sticker last chosen, if the look still matches it; otherwise the one named for the palette.
  function sync() {
    var look = window.blygletLook.get();
    var last = null;
    try { last = localStorage.getItem(KEY); } catch (e) {}
    var lastSticker = stickers.filter(function (s) { return s.dataset.icon === last; })[0];
    var key = lastSticker && fits(lastSticker, look) ? last : CANONICAL[look.palette];
    stickers.forEach(function (s) { s.setAttribute('aria-pressed', s.dataset.icon === key ? 'true' : 'false'); });
  }

  stickers.forEach(function (s) {
    s.addEventListener('click', function () {
      try { localStorage.setItem(KEY, s.dataset.icon); } catch (e) {}
      window.blygletLook.set({ palette: s.dataset.palette, mode: s.dataset.mode });
      var name = s.querySelector('img').alt;
      status.textContent = s.dataset.nearest
        ? name + ' has no theme of its own here, so the page is in ' + THEMES[s.dataset.palette] + ', the nearest.'
        : '';
    });
  });
  document.addEventListener('blyglet:look', function () {
    sync();
    // After a choice in the menu, the explanation stays only while a sticker without a theme is still pressed.
    if (!stickers.some(function (s) { return s.getAttribute('aria-pressed') === 'true' && s.dataset.nearest; })) status.textContent = '';
  });
  sync();
})();
