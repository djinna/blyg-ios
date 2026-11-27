// Option A's mockup: the app icons as the site's color switcher (docs/icons-a.md). Each icon button sets the
// look through window.blygletLook (assets/switcher.js), so the Color menu, the nav and hero icons and the
// appearance button all follow, and a choice made in the menu moves the pressed icon. Without JavaScript the
// icons still show; they just don't switch anything.
(function () {
  'use strict';
  var picker = document.querySelector('.icon-picker');
  var status = document.querySelector('.icon-pick-status');
  if (!picker || !status || !window.blygletLook) return;

  var KEY = 'blyglet-site-icon';
  var CANONICAL = { blue: 'pencil-blue', pink: 'piglet-pink', moss: 'moss', butter: 'butter' };
  var THEMES = { blue: 'Pencil blue', pink: 'Piglet pink', moss: 'Moss', butter: 'Butter' };
  var buttons = Array.prototype.slice.call(picker.querySelectorAll('.icon-pick'));

  function fits(button, look) {
    return button.dataset.palette === look.palette && (!button.dataset.mode || button.dataset.mode === look.mode);
  }

  // Pressed: the icon last chosen here, if the look still matches it; otherwise the icon named for the palette.
  function sync() {
    var look = window.blygletLook.get();
    var last = null;
    try { last = localStorage.getItem(KEY); } catch (e) {}
    var lastButton = buttons.filter(function (b) { return b.dataset.icon === last; })[0];
    var key = lastButton && fits(lastButton, look) ? last : CANONICAL[look.palette];
    buttons.forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.icon === key ? 'true' : 'false'); });
  }

  function said(button) {
    var name = button.querySelector('img').alt;
    var theme = THEMES[button.dataset.palette];
    if (button.dataset.mode) return name + ': this page is in ' + theme + ', ' + button.dataset.mode + '.';
    if (name === theme) return name + ': this page is in ' + theme + ' now.';
    return name + ' has no theme of its own here, so this page is in ' + theme + ', the nearest.';
  }

  buttons.forEach(function (b) {
    b.addEventListener('click', function () {
      try { localStorage.setItem(KEY, b.dataset.icon); } catch (e) {}
      window.blygletLook.set({ palette: b.dataset.palette, mode: b.dataset.mode });
      status.textContent = said(b);
    });
  });
  document.addEventListener('blyglet:look', sync);
  status.hidden = false;
  sync();
})();
