// The site's type, color and appearance switcher. Adapted from Jenna's switcher on her own site (2026-11-23).
// The choices persist in this browser's localStorage only. Load it in <head> so the page never flashes the
// default look; the bar mounts itself into <div id="theme-bar"> once the page is parsed.
(function () {
  'use strict';

  var FONTS = {
    blyglet: 'Blyglet',
    jetbrains: 'JetBrains',
    martian: 'Martian',
    plex: 'Plex',
    geist: 'Geist',
    literata: 'Literata',
    'ibm-serif': 'Plex Serif',
    'source-serif': 'Source Serif',
    newsreader: 'Newsreader',
  };
  var GROUPS = [
    { label: 'The app’s own', keys: ['blyglet'] },
    { label: 'Mono/Sans', keys: ['jetbrains', 'martian', 'plex', 'geist'] },
    { label: 'Serif', keys: ['literata', 'ibm-serif', 'source-serif', 'newsreader'] },
  ];
  // The app's color themes that follow light and dark (Paper and Ink are the appearance button's job here).
  var PALETTES = { blue: 'Pencil blue', pink: 'Piglet pink', moss: 'Moss', butter: 'Butter' };
  var PALETTE_KEYS = Object.keys(PALETTES);
  var MODES = ['system', 'light', 'dark'];
  var MODE_GLYPH = { system: '◐', light: '☀', dark: '☾' };
  var MODE_LABEL = {
    system: 'Appearance: system (click for light)',
    light: 'Appearance: light (click for dark)',
    dark: 'Appearance: dark (click for system)',
  };
  var STORAGE = 'blyglet-site-look-v1';

  var root = document.documentElement;
  var mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  var state = { font: 'jetbrains', palette: 'blue', mode: 'system' }; // the default look; the layout's CSS matches it
  try {
    var saved = JSON.parse(localStorage.getItem(STORAGE));
    if (saved) {
      if (FONTS[saved.font]) state.font = saved.font;
      if (PALETTES[saved.palette]) state.palette = saved.palette;
      if (MODES.indexOf(saved.mode) >= 0) state.mode = saved.mode;
    }
  } catch (e) { /* first visit, or storage blocked: the defaults */ }

  function save() {
    try { localStorage.setItem(STORAGE, JSON.stringify(state)); } catch (e) {}
  }

  function apply(bar) {
    root.setAttribute('data-font', state.font);
    root.setAttribute('data-palette', state.palette);
    root.classList.toggle('dark', state.mode === 'dark');
    root.classList.toggle('light', state.mode === 'light');
    if (!bar) return;
    bar.querySelector('.font-name').textContent = FONTS[state.font];
    bar.querySelectorAll('.theme-opt').forEach(function (b) {
      var active = b.dataset.font ? b.dataset.font === state.font : b.dataset.palette === state.palette;
      b.classList.toggle('active', active);
      b.setAttribute('aria-pressed', active ? 'true' : 'false');
      b.querySelector('.theme-current').hidden = !active;
    });
    var mode = bar.querySelector('.dark-btn');
    mode.textContent = MODE_GLYPH[state.mode];
    mode.title = MODE_LABEL[state.mode];
    mode.setAttribute('aria-label', MODE_LABEL[state.mode]);
  }

  function option(attr, key, name, sample, swatch) {
    return '<button type="button" class="theme-opt" data-' + attr + '="' + key + '" aria-pressed="false">' +
      '<span class="theme-opt-main"><span class="theme-opt-name">' +
        (swatch ? '<span class="palette-swatch" aria-hidden="true"></span>' : '') + name +
      '</span><span class="theme-current" hidden>[current]</span></span>' +
      (sample ? '<span class="theme-sample">A quiet line of proof text</span>' : '') +
    '</button>';
  }

  // A change made here or through window.blygletLook: shown, saved, and announced to the page.
  var barEl = null;
  function commit() {
    apply(barEl); save();
    try { document.dispatchEvent(new CustomEvent('blyglet:look', { detail: { palette: state.palette, mode: state.mode } })); } catch (e) {}
  }
  // For other parts of the page (the app icons): read the look, or set its palette and, optionally, its mode.
  window.blygletLook = {
    get: function () { return { font: state.font, palette: state.palette, mode: state.mode }; },
    set: function (next) {
      if (next.palette && PALETTES[next.palette]) state.palette = next.palette;
      if (next.mode && MODES.indexOf(next.mode) >= 0) state.mode = next.mode;
      commit();
    },
  };

  function mount(bar) {
    barEl = bar;
    bar.classList.add('theme-bar');
    bar.innerHTML =
      '<button type="button" class="font-name" aria-haspopup="true" aria-expanded="false" title="Type and color"></button>' +
      '<div class="font-options" aria-label="Type and color">' +
        GROUPS.map(function (g) {
          return '<div class="theme-opt-group"><div class="theme-opt-label">' + g.label + '</div>' +
            g.keys.map(function (k) { return option('font', k, FONTS[k], true, false); }).join('') + '</div>';
        }).join('') +
        '<div class="theme-opt-group"><div class="theme-opt-label">Color</div>' +
          '<div class="palette-note">The app’s themes · light and dark</div>' +
          PALETTE_KEYS.map(function (k) { return option('palette', k, PALETTES[k], false, true); }).join('') +
        '</div>' +
      '</div>' +
      '<span class="theme-sep"></span>' +
      '<button type="button" class="dark-btn"></button>';

    var nameEl = bar.querySelector('.font-name');
    var options = bar.querySelector('.font-options');
    var expanded = false;
    function fit() {
      if (!expanded) return;
      options.style.left = ''; options.style.right = '';
      var rect = options.getBoundingClientRect();
      var left = Math.max(12, Math.min(rect.left, window.innerWidth - rect.width - 12));
      if (left !== rect.left) {
        options.style.left = (left - bar.getBoundingClientRect().left) + 'px';
        options.style.right = 'auto';
      }
      options.style.maxHeight = Math.max(0, window.innerHeight - rect.top - 12) + 'px';
    }
    function setExpanded(next) {
      expanded = next;
      bar.classList.toggle('expanded', expanded);
      nameEl.setAttribute('aria-expanded', expanded ? 'true' : 'false');
      fit();
    }
    window.addEventListener('resize', fit);
    nameEl.addEventListener('click', function () { setExpanded(!expanded); });
    document.addEventListener('click', function (e) { if (expanded && !bar.contains(e.target)) setExpanded(false); });
    document.addEventListener('keydown', function (e) { if (expanded && e.key === 'Escape') setExpanded(false); });
    bar.querySelectorAll('.theme-opt').forEach(function (btn) {
      btn.addEventListener('click', function () {
        if (this.dataset.font) state.font = this.dataset.font; else state.palette = this.dataset.palette;
        setExpanded(false);
        commit();
      });
    });
    bar.querySelector('.dark-btn').addEventListener('click', function () {
      state.mode = MODES[(MODES.indexOf(state.mode) + 1) % MODES.length];
      commit();
    });
    if (mq) {
      var onChange = function () { if (state.mode === 'system') apply(bar); };
      if (mq.addEventListener) mq.addEventListener('change', onChange); else if (mq.addListener) mq.addListener(onChange);
    }
    apply(bar);
  }

  apply(null); // before first paint
  document.addEventListener('DOMContentLoaded', function () {
    var bar = document.getElementById('theme-bar');
    if (bar) mount(bar);
  });
})();
