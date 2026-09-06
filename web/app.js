// Mac-multi-server panel — minimal progressive enhancement.
// (Bundle selection is pure CSS: input:checked + .envcard. No JS needed for it.)

// deploy panel toggle (populated view: FAB opens the form, ✕ closes it)
function openDeploy(){ document.body.classList.add('show-deploy'); window.scrollTo(0,0); }
function closeDeploy(){ document.body.classList.remove('show-deploy'); }

// deploy form: size presets (S/M/L) + Custom, GB→MB, live summary.
(function () {
  var form = document.getElementById('deployForm'); if (!form) return;
  var PRE = { s:{cpu:1,ram:2,disk:20}, m:{cpu:2,ram:4,disk:40}, l:{cpu:4,ram:8,disk:80} };
  var fCpu=document.getElementById('fCpu'), fMem=document.getElementById('fMem'), fDisk=document.getElementById('fDisk');
  var cCpu=document.getElementById('cCpu'), cRam=document.getElementById('cRam'), cDisk=document.getElementById('cDisk');
  var box=document.getElementById('customBox'), sum=document.getElementById('deploySummary');
  function size(){ var r=form.querySelector('input[name=size]:checked'); return r?r.value:'m'; }
  function bundleName(){ var b=form.querySelector('.envgrid input:checked');
    var h=b&&b.parentNode.querySelector('h3'); return h?h.textContent:'Ubuntu'; }
  function vals(){ var s=size();
    if (s==='custom') return { cpu:+cCpu.value||1, ram:+cRam.value||1, disk:+cDisk.value||10 };
    return PRE[s]||PRE.m; }
  function apply(){
    var v=vals();
    box.hidden = (size()!=='custom');
    fCpu.value=v.cpu; fMem.value=Math.round(v.ram*1024); fDisk.value=v.disk;
    var nm=bundleName(), base=(nm==='Blank Ubuntu')?'Ubuntu 24.04':(nm+' on Ubuntu');
    sum.textContent = base+' · '+v.cpu+' vCPU · '+v.ram+' GB · '+v.disk+' GB';
  }
  form.addEventListener('change', apply);
  [cCpu,cRam,cDisk].forEach(function(i){ if(i) i.addEventListener('input', apply); });
  apply();
})();

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
