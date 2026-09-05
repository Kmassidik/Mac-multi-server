import Foundation

/// Server-rendered HTML. Light identity matched to vantis.sh:
/// white ground, black text, spring-green accent, geometric grotesque, green highlighter.
enum Pages {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let head = """
    <meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
    <link rel='preconnect' href='https://fonts.googleapis.com'>
    <link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>
    <link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Space+Grotesk:wght@500;600;700&display=swap' rel='stylesheet'>
    <style>
    :root{
      --bg:#ffffff; --soft:#f6f8f6; --line:#e6e8e6; --fg:#0a0b0a; --muted:#6b7280;
      --green:#5fe490; --green-h:#4ad97f; --danger:#e5484d;
      --disp:'Space Grotesk',system-ui,sans-serif; --sans:'Inter',system-ui,sans-serif;
    }
    *{box-sizing:border-box} html,body{height:100%}
    body{margin:0;color:var(--fg);font-family:var(--sans);background:var(--bg)}
    a{color:var(--fg)} a:hover{opacity:.7}
    .mark{background:var(--green);padding:.02em .18em;border-radius:4px;box-decoration-break:clone;-webkit-box-decoration-break:clone}
    .pill{display:inline-block;background:var(--green);color:#0a0b0a;font-family:var(--sans);
      font-size:11px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;padding:5px 11px;border-radius:999px}
    .auth{min-height:100%;display:grid;place-items:center;padding:24px;background:
      radial-gradient(900px 420px at 50% -10%, rgba(95,228,144,.14), transparent 70%), var(--bg)}
    .card{width:100%;max-width:410px;background:#fff;border:1px solid var(--line);
      border-radius:18px;padding:32px;box-shadow:0 20px 50px -24px rgba(10,11,10,.18)}
    .wordmark{font-family:var(--disp);font-weight:700;font-size:24px;letter-spacing:-.02em;margin:14px 0 2px;display:flex;align-items:center;gap:9px}
    .dot{width:9px;height:9px;border-radius:50%;background:var(--green);box-shadow:0 0 0 3px rgba(95,228,144,.28)}
    .sub{color:var(--muted);font-size:14px;margin:0 0 22px}
    label{display:block;font-size:13px;font-weight:500;color:var(--fg);margin:15px 0 6px}
    .inp{position:relative}
    input{width:100%;background:#fff;border:1px solid #d8dcd8;border-radius:11px;
      padding:12px 44px 12px 13px;color:var(--fg);font:400 15px var(--sans)}
    input::placeholder{color:#9aa3a0}
    input:focus{outline:none;border-color:var(--green-h);box-shadow:0 0 0 3px rgba(95,228,144,.3)}
    .eye{position:absolute;right:6px;top:50%;transform:translateY(-50%);background:none;border:0;
      color:var(--muted);cursor:pointer;padding:8px;border-radius:8px;line-height:0}
    .eye:hover{color:var(--fg)} .eye:focus-visible{outline:2px solid var(--green-h)}
    button.go{width:100%;margin-top:22px;background:var(--green);color:#0a0b0a;font:600 15px var(--sans);
      border:0;border-radius:11px;padding:13px;cursor:pointer;transition:background .15s}
    button.go:hover{background:var(--green-h)} button.go:disabled{opacity:.5;cursor:not-allowed}
    .hint{font-size:13px;color:var(--muted);margin-top:8px;min-height:16px}
    .hint.ok{color:#1a8f4a} .hint.no{color:var(--danger)}
    .err{background:#fdeaea;border:1px solid #f6c9ca;color:#a3282c;font-size:13px;border-radius:10px;padding:10px 12px;margin-bottom:16px}
    @media (prefers-reduced-motion:reduce){*{transition:none!important}}
    </style>
    """

    static let eye = """
    <button type='button' class='eye' aria-label='Show password' aria-pressed='false'>
    <svg width='19' height='19' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z'/><circle cx='12' cy='12' r='3'/></svg>
    </button>
    """

    static let eyeJS = """
    <script>
    document.querySelectorAll('.eye').forEach(function(b){b.addEventListener('click',function(){
      var i=b.parentNode.querySelector('input'); var on=i.type==='password';
      i.type=on?'text':'password'; b.setAttribute('aria-pressed',on); i.focus();
    });});
    </script>
    """

    static func shell(_ title: String, _ body: String) -> String {
        "<!doctype html><html lang='en'><head><title>\(title)</title>\(head)</head><body>\(body)</body></html>"
    }

    static func setup(error: String?) -> String {
        let user = Config.shared.or("PANEL_ADMIN_USER", "admin")
        return shell("Set up · Mac-multi-server", """
        <div class='auth'><div class='card'>
          <span class='pill'>Control plane</span>
          <div class='wordmark'><span class='dot'></span>Mac-multi-server</div>
          <p class='sub'>First run — create your <span class='mark'>admin login</span>.</p>
          \(error.map { "<div class='err'>\(esc($0))</div>" } ?? "")
          <form method='post' action='/setup'>
            <label for='u'>Username</label>
            <div class='inp'><input id='u' name='username' value='\(esc(user))' autocomplete='username' required></div>
            <label for='pw'>Password</label>
            <div class='inp'><input id='pw' name='password' type='password' autocomplete='new-password' placeholder='at least 8 characters' required>\(eye)</div>
            <label for='cf'>Confirm password</label>
            <div class='inp'><input id='cf' name='confirm' type='password' autocomplete='new-password' required>\(eye)</div>
            <div id='hint' class='hint'></div>
            <button id='go' class='go' type='submit' disabled>Create admin &amp; sign in</button>
          </form>
        </div></div>
        \(eyeJS)
        <script>
        var p=document.getElementById('pw'),c=document.getElementById('cf'),g=document.getElementById('go'),h=document.getElementById('hint');
        function chk(){var l=p.value.length;
          if(!p.value&&!c.value){h.textContent='';h.className='hint';g.disabled=true;return;}
          if(l<8){h.textContent='Use at least 8 characters ('+l+'/8).';h.className='hint no';g.disabled=true;return;}
          if(c.value&&p.value!==c.value){h.textContent="Passwords don't match yet.";h.className='hint no';g.disabled=true;return;}
          if(p.value===c.value){h.textContent='Passwords match.';h.className='hint ok';g.disabled=false;}
          else{h.textContent='';h.className='hint';g.disabled=true;}}
        p.addEventListener('input',chk);c.addEventListener('input',chk);chk();
        </script>
        """)
    }

    static func login(error: String?) -> String {
        shell("Sign in · Mac-multi-server", """
        <div class='auth'><div class='card'>
          <span class='pill'>Control plane</span>
          <div class='wordmark'><span class='dot'></span>Mac-multi-server</div>
          <p class='sub'>Sign in to manage your <span class='mark'>servers</span>.</p>
          \(error.map { "<div class='err'>\(esc($0))</div>" } ?? "")
          <form method='post' action='/login'>
            <label for='u'>Username</label>
            <div class='inp'><input id='u' name='username' autocomplete='username' autofocus required></div>
            <label for='pw'>Password</label>
            <div class='inp'><input id='pw' name='password' type='password' autocomplete='current-password' required>\(eye)</div>
            <button class='go' type='submit'>Sign in</button>
          </form>
        </div></div>
        \(eyeJS)
        """)
    }

    static let dashCSS = """
    <style>
    .wrap{max-width:1040px;margin:0 auto;padding:26px 24px}
    header{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:1px solid var(--line);padding-bottom:18px;margin-bottom:22px}
    .brand{font-family:var(--disp);font-weight:700;font-size:20px;letter-spacing:-.02em;display:flex;align-items:center;gap:9px}
    .who{color:var(--muted);font-size:13px;margin-top:4px}
    .btn{font:500 13px var(--sans);border:1px solid #d8dcd8;background:#fff;color:var(--fg);border-radius:10px;padding:9px 13px;cursor:pointer}
    .btn:hover{border-color:#0a0b0a}
    .btn.accent{background:var(--green);border-color:var(--green);color:#0a0b0a;font-weight:600}
    .btn.accent:hover{background:var(--green-h)}
    .btn.danger{border-color:#f0c4c5;color:var(--danger);background:#fff}
    .btn.danger:hover{border-color:var(--danger)}
    .panel{background:var(--soft);border:1px solid var(--line);border-radius:16px;padding:20px;margin-bottom:22px}
    .panel h2{font-family:var(--disp);font-weight:600;font-size:16px;margin:0 0 15px}
    .row{display:flex;gap:12px;flex-wrap:wrap;align-items:end}.row>div{flex:1;min-width:112px}
    .row label{margin-top:0}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:16px}
    .vps{background:#fff;border:1px solid var(--line);border-radius:16px;padding:18px}
    .vps .top{display:flex;justify-content:space-between;align-items:center;margin-bottom:9px}
    .vps b{font-family:var(--disp);font-weight:600;font-size:16px}
    .tag{font-size:11px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;padding:3px 10px;border-radius:999px;border:1px solid var(--line);color:var(--muted)}
    .tag.run{background:var(--green);border-color:var(--green);color:#0a0b0a} .tag.dep{background:#fff4d6;border-color:#f0d998;color:#8a6d1a}
    .kv{font-size:13px;margin:5px 0} .kv b{color:var(--muted);font-weight:500;display:inline-block;width:52px;font-size:12px}
    code{font-family:ui-monospace,'SF Mono',monospace;font-size:12px;background:var(--soft);border:1px solid var(--line);border-radius:6px;padding:1px 6px}
    .notice{background:rgba(95,228,144,.16);border:1px solid var(--green);color:#146a37;border-radius:11px;padding:11px 13px;margin-bottom:18px;font-size:13px}
    .empty{color:var(--muted);text-align:center;padding:34px}
    label{font-size:12px;color:var(--muted);font-weight:500}
    select,.wrap input{width:100%;background:#fff;border:1px solid #d8dcd8;border-radius:10px;padding:10px 11px;color:var(--fg);font:400 14px var(--sans)}
    select:focus,.wrap input:focus{outline:none;border-color:var(--green-h);box-shadow:0 0 0 3px rgba(95,228,144,.3)}
    </style>
    """

    static func dashboard(user: String, vpsList: [VPS], csrf: String, notice: String?) -> String {
        let jump = Config.shared["PANEL_SSH_JUMP"]
        let bundles = Config.shared.or("BUNDLES", "blank,openclaw,hermes")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let opts = bundles.map { "<option value='\(esc($0))'>\(esc($0))</option>" }.joined()
        let mon = Config.shared["GRAFANA_SUBDOMAIN"], dom = Config.shared["DOMAIN"]
        let monLink = (!mon.isEmpty && !dom.isEmpty) ? " · <a href='https://\(esc(mon)).\(esc(dom))' target='_blank'>monitoring</a>" : ""

        let cards = vpsList.isEmpty
            ? "<div class='vps empty'>No servers yet — deploy one above.</div>"
            : vpsList.map { v in
                let tag = v.status == "running" ? "tag run" : (v.status == "deploying" ? "tag dep" : "tag")
                let host = v.hostname.isEmpty ? "" : "<div class='kv'><b>Host</b> <a href='https://\(esc(v.hostname))' target='_blank'>\(esc(v.hostname))</a></div>"
                let ssh = "ssh -J \(jump.isEmpty ? "&lt;mac&gt;" : esc(jump)) admin@\(esc(v.ip))"
                return """
                <div class='vps'>
                  <div class='top'><b>\(esc(v.name))</b><span class='\(tag)'>\(esc(v.status))</span></div>
                  <div class='kv' style='color:var(--muted)'>Ubuntu · \(v.cpu) vCPU · \(v.mem_mb) MB · \(v.disk_gb) GB · \(esc(v.bundle))</div>
                  <div class='kv'><b>IP</b> <code>\(esc(v.ip))</code></div>
                  \(host)
                  <div class='kv'><b>SSH</b> <code>\(ssh)</code></div>
                  <form method='post' action='/destroy' onsubmit="return confirm('Destroy \(esc(v.name))? This is permanent.')" style='margin-top:12px'>
                    <input type='hidden' name='csrf' value='\(csrf)'><input type='hidden' name='name' value='\(esc(v.name))'>
                    <button class='btn danger' type='submit'>Destroy</button>
                  </form>
                </div>
                """
            }.joined()

        return shell("Mac-multi-server", dashCSS + """
        <div class='wrap'>
          <header>
            <div>
              <div class='brand'><span class='dot'></span>Mac-multi-server</div>
              <div class='who'>\(esc(user))\(monLink)</div>
            </div>
            <form method='post' action='/logout'><input type='hidden' name='csrf' value='\(csrf)'><button class='btn'>Sign out</button></form>
          </header>
          \(notice.map { "<div class='notice'>\(esc($0))</div>" } ?? "")
          <div class='panel'>
            <h2>Deploy a server</h2>
            <form method='post' action='/deploy'>
              <input type='hidden' name='csrf' value='\(csrf)'>
              <div class='row'>
                <div><label>Bundle</label><select name='bundle'>\(opts)</select></div>
                <div><label>vCPU</label><input name='cpu' type='number' value='\(Config.shared.or("VPS_DEFAULT_CPU","2"))' min='1' max='16'></div>
                <div><label>RAM (MB)</label><input name='mem' type='number' value='\(Config.shared.or("VPS_DEFAULT_MEM_MB","4096"))' min='512'></div>
                <div><label>Disk (GB)</label><input name='disk' type='number' value='\(Config.shared.or("VPS_DEFAULT_DISK_GB","40"))' min='10'></div>
                <div style='flex:0'><label>&nbsp;</label><button class='btn accent' type='submit'>Deploy</button></div>
              </div>
            </form>
          </div>
          <div class='grid'>\(cards)</div>
        </div>
        """)
    }
}
