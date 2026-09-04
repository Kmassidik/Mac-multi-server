import Foundation

/// Server-rendered HTML. No framework, no external assets — one honest web app.
enum Pages {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let css = """
    :root{--bg:#0d1117;--card:#161b22;--line:#30363d;--fg:#e6edf3;--mut:#8b949e;--accent:#2f81f7;--ok:#3fb950;--danger:#f85149}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,system-ui,sans-serif}
    a{color:var(--accent);text-decoration:none}.wrap{max-width:960px;margin:0 auto;padding:24px}
    header{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid var(--line);padding-bottom:16px;margin-bottom:24px}
    h1{font-size:18px;margin:0}.mut{color:var(--mut)}
    .card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin-bottom:16px}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}
    label{display:block;font-size:12px;color:var(--mut);margin:8px 0 4px}
    input,select,button{font:inherit;padding:9px 11px;border-radius:8px;border:1px solid var(--line);background:#0d1117;color:var(--fg)}
    input,select{width:100%}
    button{cursor:pointer;background:var(--accent);border-color:var(--accent);color:#fff;font-weight:600}
    button.ghost{background:transparent;color:var(--fg)}button.danger{background:transparent;border-color:var(--danger);color:var(--danger)}
    .row{display:flex;gap:12px;flex-wrap:wrap;align-items:end}.row>div{flex:1;min-width:110px}
    .badge{font-size:11px;padding:2px 8px;border-radius:20px;border:1px solid var(--line)}
    .badge.run{color:var(--ok);border-color:var(--ok)}.badge.dep{color:#d29922;border-color:#d29922}
    .kv{font-size:13px;margin:6px 0}.kv b{color:var(--mut);font-weight:500;display:inline-block;width:64px}
    code{background:#0d1117;border:1px solid var(--line);border-radius:6px;padding:1px 6px;font-size:12px}
    .center{max-width:360px;margin:12vh auto}.err{color:var(--danger);font-size:13px;margin:8px 0}
    """

    static func page(_ title: String, _ body: String) -> String {
        "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>\(title)</title><style>\(css)</style></head><body>\(body)</body></html>"
    }

    static func setup(error: String?) -> String {
        page("Set up · Mac-multi-server", """
        <div class='wrap'><div class='center card'>
        <h1>Mac-multi-server</h1><p class='mut'>First run — create the admin login.</p>
        \(error.map { "<div class='err'>\(esc($0))</div>" } ?? "")
        <form method='post' action='/setup'>
        <label>Admin username</label><input name='username' value='\(esc(Config.shared["PANEL_ADMIN_USER"].isEmpty ? "admin" : Config.shared["PANEL_ADMIN_USER"]))' required>
        <label>Password (min 8)</label><input name='password' type='password' minlength='8' required>
        <label>Confirm password</label><input name='confirm' type='password' minlength='8' required>
        <div style='height:12px'></div><button type='submit'>Create admin</button>
        </form></div></div>
        """)
    }

    static func login(error: String?) -> String {
        page("Sign in · Mac-multi-server", """
        <div class='wrap'><div class='center card'>
        <h1>Mac-multi-server</h1><p class='mut'>Sign in to manage your VPS.</p>
        \(error.map { "<div class='err'>\(esc($0))</div>" } ?? "")
        <form method='post' action='/login'>
        <label>Username</label><input name='username' required autofocus>
        <label>Password</label><input name='password' type='password' required>
        <div style='height:12px'></div><button type='submit'>Sign in</button>
        </form></div></div>
        """)
    }

    static func dashboard(user: String, vpsList: [VPS], csrf: String, notice: String?) -> String {
        let jump = Config.shared["PANEL_SSH_JUMP"]
        let bundles = (Config.shared["BUNDLES"].isEmpty ? "blank,openclaw" : Config.shared["BUNDLES"])
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let opts = bundles.map { "<option value='\(esc($0))'>\(esc($0))</option>" }.joined()

        let cards = vpsList.isEmpty
            ? "<div class='card mut'>No VPS yet — deploy one above.</div>"
            : vpsList.map { v in
                let badge = v.status == "running" ? "badge run" : (v.status == "deploying" ? "badge dep" : "badge")
                let host = v.hostname.isEmpty ? "" : "<div class='kv'><b>Host</b> <a href='https://\(esc(v.hostname))' target='_blank'>\(esc(v.hostname))</a></div>"
                let ssh = "ssh -J \(jump.isEmpty ? "&lt;mac&gt;" : esc(jump)) admin@\(esc(v.ip))"
                return """
                <div class='card'>
                  <div style='display:flex;justify-content:space-between;align-items:center'>
                    <b>\(esc(v.name))</b><span class='\(badge)'>\(esc(v.status))</span>
                  </div>
                  <div class='kv mut'>Ubuntu · \(v.cpu) vCPU · \(v.mem_mb) MB · \(v.disk_gb) GB · \(esc(v.bundle))</div>
                  <div class='kv'><b>IP</b> <code>\(esc(v.ip))</code></div>
                  \(host)
                  <div class='kv'><b>SSH</b> <code>\(ssh)</code></div>
                  <form method='post' action='/destroy' onsubmit="return confirm('Destroy \(esc(v.name))? This is permanent.')" style='margin-top:10px'>
                    <input type='hidden' name='csrf' value='\(csrf)'><input type='hidden' name='name' value='\(esc(v.name))'>
                    <button class='danger' type='submit'>Destroy</button>
                  </form>
                </div>
                """
            }.joined()

        let monitor = Config.shared["GRAFANA_SUBDOMAIN"]
        let domain = Config.shared["DOMAIN"]
        let monLink = (!monitor.isEmpty && !domain.isEmpty) ? " · <a href='https://\(esc(monitor)).\(esc(domain))' target='_blank'>monitoring</a>" : ""

        return page("Mac-multi-server", """
        <div class='wrap'>
        <header>
          <div><h1>Mac-multi-server</h1><span class='mut'>\(esc(user))\(monLink)</span></div>
          <form method='post' action='/logout'><input type='hidden' name='csrf' value='\(csrf)'><button class='ghost'>Sign out</button></form>
        </header>
        \(notice.map { "<div class='card' style='border-color:var(--accent)'>\(esc($0))</div>" } ?? "")
        <div class='card'>
          <b>Deploy a VPS</b>
          <form method='post' action='/deploy'>
            <input type='hidden' name='csrf' value='\(csrf)'>
            <div class='row' style='margin-top:10px'>
              <div><label>Bundle</label><select name='bundle'>\(opts)</select></div>
              <div><label>vCPU</label><input name='cpu' type='number' value='\(Config.shared["VPS_DEFAULT_CPU"].isEmpty ? "2" : Config.shared["VPS_DEFAULT_CPU"])' min='1' max='16'></div>
              <div><label>RAM (MB)</label><input name='mem' type='number' value='\(Config.shared["VPS_DEFAULT_MEM_MB"].isEmpty ? "4096" : Config.shared["VPS_DEFAULT_MEM_MB"])' min='512'></div>
              <div><label>Disk (GB)</label><input name='disk' type='number' value='\(Config.shared["VPS_DEFAULT_DISK_GB"].isEmpty ? "40" : Config.shared["VPS_DEFAULT_DISK_GB"])' min='10'></div>
              <div style='flex:0'><label>&nbsp;</label><button type='submit'>Deploy</button></div>
            </div>
          </form>
        </div>
        <div class='grid'>\(cards)</div>
        </div>
        """)
    }
}
