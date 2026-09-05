// Mac-multi-server panel — small progressive-enhancement JS.
// Each block guards on element presence, so one file works across setup/login/dashboard.

// show / hide password
document.querySelectorAll('.eye').forEach(function (b) {
  b.addEventListener('click', function () {
    var i = b.parentNode.querySelector('input');
    var on = i.type === 'password';
    i.type = on ? 'text' : 'password';
    b.setAttribute('aria-pressed', on);
    i.focus();
  });
});

// setup: live password validation (>=8 chars + match) -> enable submit
(function () {
  var p = document.getElementById('pw'), c = document.getElementById('cf'),
      g = document.getElementById('go'), h = document.getElementById('hint');
  if (!p || !c || !g || !h) return;
  function chk() {
    var l = p.value.length;
    if (!p.value && !c.value) { h.textContent = ''; h.className = 'hint'; g.disabled = true; return; }
    if (l < 8) { h.textContent = 'Use at least 8 characters (' + l + '/8).'; h.className = 'hint no'; g.disabled = true; return; }
    if (c.value && p.value !== c.value) { h.textContent = "Passwords don't match yet."; h.className = 'hint no'; g.disabled = true; return; }
    if (p.value === c.value) { h.textContent = 'Passwords match.'; h.className = 'hint ok'; g.disabled = false; }
    else { h.textContent = ''; h.className = 'hint'; g.disabled = true; }
  }
  p.addEventListener('input', chk); c.addEventListener('input', chk); chk();
})();

// dashboard: bundle card selection -> hidden input
(function () {
  var cards = document.querySelectorAll('.bcard'), field = document.getElementById('bundle');
  if (!cards.length || !field) return;
  function pick(c) {
    cards.forEach(function (x) { x.classList.remove('sel'); x.setAttribute('aria-checked', 'false'); });
    c.classList.add('sel'); c.setAttribute('aria-checked', 'true'); field.value = c.dataset.key;
  }
  cards.forEach(function (c) {
    c.addEventListener('click', function () { pick(c); });
    c.addEventListener('keydown', function (e) { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); pick(c); } });
  });
})();
