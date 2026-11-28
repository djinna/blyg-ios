// The app-icon stickers by the front page's hero. A sticker sets the icon, as choosing one does in the app: the
// nav and hero show it (assets/switcher.js applies it). It brings its colors along: its own theme, or the
// nearest of the site's four. Paper and Ink are themes that fix light or dark, so they also set the mode, as
// the appearance button (◐) does; picking another sticker afterwards hands the mode back to the system.
// Without JavaScript the stickers show and do nothing.
(function () {
  'use strict';
  var sheet = document.querySelector('.sticker-sheet');
  if (!sheet || !window.blygletLook) return;
  var stickers = Array.prototype.slice.call(sheet.querySelectorAll('.sticker'));

  function byIcon(icon) { return stickers.filter(function (s) { return s.dataset.icon === icon; })[0]; }

  function sync() {
    var icon = window.blygletLook.get().icon || 'pencil-blue';
    stickers.forEach(function (s) { s.setAttribute('aria-pressed', s.dataset.icon === icon ? 'true' : 'false'); });
  }

  stickers.forEach(function (s) {
    s.addEventListener('click', function () {
      var look = window.blygletLook.get();
      var next = { icon: s.dataset.icon, palette: s.dataset.palette };
      if (s.dataset.mode) {
        next.mode = s.dataset.mode;
      } else {
        // Leaving Paper or Ink: the light or dark it set goes back to the system's, unless ◐ changed it since.
        var was = byIcon(look.icon);
        if (was && was.dataset.mode && was.dataset.mode === look.mode) next.mode = 'system';
      }
      window.blygletLook.set(next);
    });
  });
  document.addEventListener('blyglet:look', sync);
  sync();
})();
