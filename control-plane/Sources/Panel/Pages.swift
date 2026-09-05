import Foundation

/// Server-rendered HTML. No framework. Graphite + machined-amber "control plane" identity.
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
    <link href='https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap' rel='stylesheet'>
    <style>
    :root{
      --bg:#0b0d11; --grid:#111520; --surface:#13171e; --surface2:#171c25; --line:#242b36;
      --fg:#e8ebf1; --muted:#8a93a2; --accent:#e0a13a; --accent2:#eab253; --ok:#5fd39a; --danger:#ff6b6b;
      --sans:'IBM Plex Sans',system-ui,sans-serif; --mono:'IBM Plex Mono',ui-monospace,monospace;
    }
    *{box-sizing:border-box} html,body{height:100%}
    body{margin:0;color:var(--fg);font-family:var(--sans);
      background:
        radial-gradient(1100px 520px at 50% -12%, rgba(224,161,58,.07), transparent 60%),
        linear-gradient(var(--grid) 1px, transparent 1px) 0 0/44px 44px,
        linear-gradient(90deg, var(--grid) 1px, transparent 1px) 0 0/44px 44px,
        var(--bg);}
    a{color:var(--accent2);text-decoration:none} a:hover{text-decoration:underline}
    .auth{min-height:100%;display:grid;place-items:center;padding:24px}
    .card{width:100%;max-width:400px;background:var(--surface);border:1px solid var(--line);
      border-radius:16px;padding:30px;box-shadow:0 30px 70px -24px rgba(0,0,0,.7)}
    .plate{display:flex;align-items:center;gap:9px;margin-bottom:4px}
    .dot{width:8px;height:8px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 3px rgba(95,211,154,.16)}
    h1{margin:0;font-weight:700;font-size:21px;letter-spacing:-.015em}
    .host{font-family:var(--mono);font-size:12px;color:var(--muted);margin:2px 0 22px}
    .lead{color:var(--muted);font-size:14px;margin:0 0 20px}
    label{display:block;font-size:12px;font-weight:500;color:var(--muted);margin:14px 0 6px}
    .inp{position:relative}
    input{width:100%;background:#0e131a;border:1px solid var(--line);border-radius:10px;
      padding:11px 42px 11px 13px;color:var(--fg);font:400 14px var(--sans)}
    input::placeholder{color:#5b636f}
    input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(224,161,58,.16)}
    .eye{position:absolute;right:6px;top:50%;transform:translateY(-50%);background:none;border:0;
      color:var(--muted);cursor:pointer;padding:7px;border-radius:8px;line-height:0}
    .eye:hover{color:var(--fg)} .eye:focus-visible{outline:2px solid var(--accent)}
    button.go{width:100%;margin-top:20px;background:var(--accent);color:#1c1305;font:600 14px var(--sans);
      border:0;border-radius:10px;padding:12px;cursor:pointer;transition:background .15s}
    button.go:hover{background:var(--accent2)} button.go:disabled{opacity:.45;cursor:not-allowed}
    .hint{font-size:12px;color:var(--muted);margin-top:7px;min-height:15px}
    .hint.ok{color:var(--ok)} .hint.no{color:var(--danger)}
    .err{background:rgba(255,107,107,.1);border:1px solid rgba(255,107,107,.35);color:#ffb0b0;
      font-size:13px;border-radius:9px;padding:9px 11px;margin-bottom:16px}
    @media (prefers-reduced-motion:reduce){*{transition:none!important}}
    </style>
    """

    // eye toggle button (SVG). Sits right after an <input type=password>.
    static let eye = """
    <button type='button' class='eye' aria-label='Show password' aria-pressed='false'>
    <svg width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z'/><circle cx='12' cy='12' r='3'/></svg>
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

    static func plate(_ line: String) -> String {
        "<div class='plate'><span class='dot'></span><h1>Mac-multi-server</h1></div><div class='host'>\(esc(line))</div>"
    }

    static func setup(error: String?) -> String {
        let user = Config.shared.or("PANEL_ADMIN_USER", "admin")
        return shell("Set up · Mac-multi-server", """
        <div class='auth'><div class='card'>
          \(plate("first run · create your admin login"))
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
          \(plate("sign in to manage your servers"))
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

    // Dashboard styles (kept lightweight; same tokens as the auth pages).
    static let dashCSS = """
    <style>
    .wrap{max-width:1000px;margin:0 auto;padding:26px 24px}
    header{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid var(--line);padding-bottom:18px;margin-bottom:22px}
    header .who{color:var(--muted);font-size:13px;margin-top:3px}
    .btn{font:500 13px var(--sans);border:1px solid var(--line);background:var(--surface);color:var(--fg);border-radius:9px;padding:8px 12px;cursor:pointer}
    .btn:hover{border-color:#333c48}
    .btn.accent{background:var(--accent);border-color:var(--accent);color:#1c1305;font-weight:600}
    .btn.accent:hover{background:var(--accent2)}
    .btn.danger{border-color:rgba(255,107,107,.4);color:var(--danger);background:transparent}
    .panel{background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:18px;margin-bottom:20px}
    .panel h2{font-size:14px;margin:0 0 14px}
    .row{display:flex;gap:12px;flex-wrap:wrap;align-items:end}.row>div{flex:1;min-width:110px}
    .row label{margin-top:0}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}
    .vps{background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:16px}
    .vps .top{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
    .vps b{font-size:15px}
    .tag{font-size:11px;padding:2px 9px;border-radius:20px;border:1px solid var(--line);color:var(--muted)}
    .tag.run{color:var(--ok);border-color:rgba(95,211,154,.4)} .tag.dep{color:var(--accent2);border-color:rgba(224,161,58,.4)}
    .kv{font-size:13px;margin:5px 0;color:var(--fg)} .kv b{color:var(--muted);font-weight:500;display:inline-block;width:52px;font-size:12px}
    code{font-family:var(--mono);font-size:12px;background:#0e131a;border:1px solid var(--line);border-radius:6px;padding:1px 6px}
    .notice{background:rgba(224,161,58,.08);border:1px solid rgba(224,161,58,.35);color:var(--accent2);border-radius:10px;padding:11px 13px;margin-bottom:18px;font-size:13px}
    .empty{color:var(--muted);text-align:center;padding:34px}
    select,.wrap input{width:100%;background:#0e131a;border:1px solid var(--line);border-radius:9px;padding:9px 11px;color:var(--fg);font:400 14px var(--sans)}
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
            ? "<div class='vps empty'>No servers yet. Deploy one above.</div>"
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
            <div>\(plate("\(esc(user))\(monLink)"))</div>
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
