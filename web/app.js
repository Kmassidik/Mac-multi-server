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

// action buttons: loading state; AJAX for lifecycle controls; live status polling.
(function () {
  function cls(s){ return s === 'running' ? 'run' : (s === 'stopped' ? '' : 'warn'); }
  function loadBtn(b){ if(!b) return; if(b.dataset.orig == null) b.dataset.orig = b.textContent;
    if(b.dataset.loading) b.textContent = b.dataset.loading; b.disabled = true; b.classList.add('loading'); }
  function resetBtns(){ document.querySelectorAll('button[data-orig]').forEach(function(b){
    b.textContent = b.dataset.orig; b.disabled = false; b.classList.remove('loading'); }); }

  // any non-AJAX form: show loading on its submit button before it navigates
  document.querySelectorAll('form:not(.ajax)').forEach(function(f){
    f.addEventListener('submit', function(){ loadBtn(f.querySelector('button[type=submit]')); });
  });

  // AJAX lifecycle controls (stop/start/restart): fire without navigating; poller reflects result
  document.querySelectorAll('form.ajax').forEach(function(f){
    f.addEventListener('submit', function(ev){
      ev.preventDefault();
      if (f.dataset.confirm && !confirm(f.dataset.confirm)) return;
      loadBtn(f.querySelector('button[type=submit]'));
      fetch(f.action, { method:'POST', credentials:'include', redirect:'manual',
        headers:{ 'Content-Type':'application/x-www-form-urlencoded' },
        body:new URLSearchParams(new FormData(f)).toString() }).catch(function(){});
      setTimeout(resetBtns, 45000);   // safety: don't get stuck if state never changes
    });
  });

  var body = document.body, name = body && body.dataset.vps;

  // detail page: poll this VPS, update the status tag + which controls show, in place
  if (name && body.classList.contains('detail')) {
    var tag = document.getElementById('stTag');
    var cur = tag ? tag.textContent.trim() : '';
    function applyDetail(s){
      resetBtns();
      if (tag){ tag.textContent = s; tag.className = 'tag ' + cls(s); }
      var stopped = s === 'stopped', running = s === 'running';
      var st = document.getElementById('cStart'), sp = document.getElementById('cStop'), rs = document.getElementById('cRestart');
      if (st) st.hidden = !stopped; if (sp) sp.hidden = stopped; if (rs) rs.hidden = stopped;
      var t = document.getElementById('termBtn'); if (t) t.disabled = !running;
    }
    setInterval(function(){
      fetch('/vps/' + encodeURIComponent(name) + '/status', { headers:{ 'Accept':'application/json' } })
        .then(function(r){ return r.ok ? r.json() : null; })
        .then(function(d){ if (d && d.status && d.status !== cur){ cur = d.status; applyDetail(d.status); } })
        .catch(function(){});
    }, 3000);
  }

  // dashboard: poll all VPS, update every card + table row (same data-vps) + count, in place
  var section = document.getElementById('serversSection');
  if (section && !(body && body.classList.contains('detail'))) {
    setInterval(function(){
      fetch('/api/vps', { headers:{ 'Accept':'application/json' } })
        .then(function(r){ return r.ok ? r.json() : null; })
        .then(function(list){ if (!list) return; var run = 0;
          list.forEach(function(v){ if (v.status === 'running') run++;
            document.querySelectorAll('[data-vps="' + v.name + '"]').forEach(function(el){
              var tg = el.querySelector('.tag'); if (tg){ tg.textContent = v.status; tg.className = 'tag ' + cls(v.status); }
            });
          });
          var c = document.querySelector('.count'); if (c) c.textContent = run + '/' + list.length + ' running';
        }).catch(function(){});
    }, 4000);

    // card/table view toggle (remembered per browser)
    var saved = null; try { saved = localStorage.getItem('mms_view'); } catch(e){}
    function setView(v){
      section.classList.toggle('as-cards', v === 'cards');
      var r = section.querySelector('input[name=view][value="' + v + '"]'); if (r) r.checked = true;
      try { localStorage.setItem('mms_view', v); } catch(e){}
    }
    if (saved === 'cards' || saved === 'table') setView(saved);
    section.querySelectorAll('input[name=view]').forEach(function(r){
      r.addEventListener('change', function(){ setView(r.value); });
    });
  }
})();

// detail page: tab switching (Overview / Monitoring / Access / Danger)
(function () {
  var tabs = document.querySelectorAll('.tab'); if (!tabs.length) return;
  tabs.forEach(function (t) {
    t.addEventListener('click', function () {
      tabs.forEach(function (x) { x.classList.remove('active'); });
      t.classList.add('active');
      var n = t.dataset.tab;
      document.querySelectorAll('.tabpanel').forEach(function (p) { p.hidden = (p.dataset.panel !== n); });
    });
  });
})();
