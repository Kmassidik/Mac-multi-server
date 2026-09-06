import Foundation

/// SSR with external templates: reads web/*.html and substitutes {{TOKENS}} server-side.
/// Design lives in web/ (style.css, *.html, app.js) — editable without recompiling.
enum Pages {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Load web/<name>, replace {{TOKENS}}, strip any leftover tokens.
    static func tpl(_ name: String, _ vars: [String: String]) -> String {
        var s = (try? String(contentsOf: rootURL("web/\(name)"), encoding: .utf8))
            ?? "<h1>template missing: \(name)</h1>"
        var vars = vars; vars["VER"] = ASSET_VER   // every page gets the cache-bust token
        for (k, v) in vars { s = s.replacingOccurrences(of: "{{\(k)}}", with: v) }
        return s.replacingOccurrences(of: "\\{\\{[A-Z_]+\\}\\}", with: "", options: .regularExpression)
    }

    static func errBlock(_ e: String?) -> String { e.map { "<div class=\"err\">\(esc($0))</div>" } ?? "" }

    /// MB → a human "N GB" (whole when even, one decimal otherwise).
    static func gb(_ mb: Int) -> String {
        let g = Double(mb) / 1024.0
        return g == g.rounded() ? "\(Int(g)) GB" : String(format: "%.1f GB", g)
    }
    /// status → tag CSS class: running (green), stopped (muted), else warning (amber).
    static func statusClass(_ s: String) -> String {
        if s == "running" { return "run" }
        if s == "stopped" { return "" }
        return "warn"   // unhealthy / flapping / restarting
    }

    static func setup(error: String?, csrf: String) -> String {
        tpl("setup.html", ["ERROR": errBlock(error), "CSRF": esc(csrf),
                           "USER": esc(Config.shared.or("PANEL_ADMIN_USER", "admin"))])
    }

    static func login(error: String?, csrf: String) -> String {
        tpl("login.html", ["ERROR": errBlock(error), "CSRF": esc(csrf)])
    }

    static func dashboard(user: String, vpsList: [VPS], csrf: String, notice: String?) -> String {
        let bl = Store.bundles()

        // environment grid: real radios (name=bundle) — active state is pure CSS (input:checked + .envcard)
        let bundles = bl.enumerated().map { (i, b) -> String in
            let logoHTML = (!b.logo.isEmpty && FileManager.default.fileExists(atPath: rootURL("web" + b.logo).path))
                ? "<img src=\"\(esc(b.logo))\" alt=\"\">" : b.icon
            return """
            <label>
              <input type="radio" name="bundle" value="\(esc(b.key))"\(i == 0 ? " checked" : "")>
              <div class="envcard">
                <div class="badge"></div>
                <div class="logo">\(logoHTML)</div>
                <span class="code">\(esc(b.code))</span>
                <h3>\(esc(b.name))</h3>
                <div class="base">🐧 \(esc(b.base))\(b.key == "blank" ? "" : " · + " + esc(b.name))</div>
                <p>\(esc(b.description))</p>
              </div>
            </label>
            """ }.joined()

        let mon = Config.shared["GRAFANA_SUBDOMAIN"], dom = Config.shared["DOMAIN"]
        let monHref = (!mon.isEmpty && !dom.isEmpty) ? "https://\(esc(mon)).\(esc(dom))" : "#"
        let announce = dom.isEmpty ? "MAC-MULTI-SERVER · CONTROL PLANE" : "MAC-MULTI-SERVER · \(esc(dom.uppercased()))"

        let servers = vpsList.isEmpty
            ? "<div class=\"empty\">No servers deployed yet — deploy one above.</div>"
            : vpsList.map { v in
                let host = v.hostname.isEmpty ? "" : " · <a href=\"https://\(esc(v.hostname))\" target=\"_blank\" onclick=\"event.stopPropagation()\">\(esc(v.hostname))</a>"
                let named = (v.label?.isEmpty == false)
                let idline = named ? "\(esc(v.name)) · " : ""
                let tag = "tag \(statusClass(v.status))"
                return """
                <div class="srvcard" data-vps="\(esc(v.name))" onclick="location.href='/vps/\(esc(v.name))'">
                  <div class="top">
                    <div class="nm">\(esc(v.display))</div>
                    <span class="\(tag)">\(esc(v.status))</span>
                  </div>
                  <div class="sub">\(idline)\(esc(v.bundle))<br>\(v.cpu) vCPU · \(gb(v.mem_mb)) · \(v.disk_gb) GB<br>\(esc(v.ip))\(host)</div>
                  <div class="acts">
                    <a class="btn line" href="/vps/\(esc(v.name))" onclick="event.stopPropagation()">Manage ↗</a>
                    <form method="post" action="/destroy" onclick="event.stopPropagation()" onsubmit="return confirm('Destroy \(esc(v.display))? This is permanent.')">
                      <input type="hidden" name="csrf" value="\(csrf)"><input type="hidden" name="name" value="\(esc(v.name))">
                      <button class="btn line" type="submit" data-loading="Terminating…">Terminate</button>
                    </form>
                  </div>
                </div>
                """
            }.joined()

        // table view (AWS/GCP-style resource list) — toggled with the card view client-side
        let serversTable = vpsList.isEmpty
            ? "<tr><td colspan=\"8\" class=\"empty\">No servers deployed yet — deploy one above.</td></tr>"
            : vpsList.map { v in
            let created = String(v.created.prefix(10))
            return """
            <tr data-vps="\(esc(v.name))" onclick="location.href='/vps/\(esc(v.name))'">
              <td class="c-name">\(esc(v.display))</td>
              <td class="mono muted">\(esc(v.name))</td>
              <td><span class="tag \(statusClass(v.status))">\(esc(v.status))</span></td>
              <td class="mono">\(esc(v.bundle))</td>
              <td class="mono">\(v.cpu)c · \(gb(v.mem_mb)) · \(v.disk_gb)G</td>
              <td class="mono">\(esc(v.ip))</td>
              <td class="mono muted">\(esc(created))</td>
              <td class="row-act">
                <a class="btn line sm" href="/vps/\(esc(v.name))" onclick="event.stopPropagation()">Manage&nbsp;↗</a>
                <form method="post" action="/destroy" onclick="event.stopPropagation()" onsubmit="return confirm('Destroy \(esc(v.display))? This is permanent.')">
                  <input type="hidden" name="csrf" value="\(csrf)"><input type="hidden" name="name" value="\(esc(v.name))">
                  <button class="btn line sm danger-text" type="submit" data-loading="…">Terminate</button>
                </form>
              </td>
            </tr>
            """
        }.joined()

        return tpl("dashboard.html", [
            "SERVERS_TABLE": serversTable,
            "MODE": vpsList.isEmpty ? "empty" : "has",
            "DEPLOYTITLE": vpsList.isEmpty ? "Deploy your first server" : "Deploy a server",
            "ANNOUNCE": announce, "USER": esc(user), "MONHREF": monHref, "CSRF": esc(csrf),
            "NOTICE": notice.map { "<div class=\"notice\">\(esc($0))</div>" } ?? "",
            "OPTCOUNT": String(bl.count), "COUNT": String(vpsList.count),
            "RUNNING": String(vpsList.filter { $0.status == "running" }.count),
            "BUNDLES": bundles,
            "CPU": esc(Config.shared.or("VPS_DEFAULT_CPU", "2")),
            "MEM": esc(Config.shared.or("VPS_DEFAULT_MEM_MB", "4096")),
            "DISK": esc(Config.shared.or("VPS_DEFAULT_DISK_GB", "40")),
            "SERVERS": servers,
        ])
    }

    /// AWS-style instance detail: specs, network, actions, web terminal.
    static func vpsDetail(vps v: VPS, csrf: String, notice: String? = nil) -> String {
        let b = Store.bundle(v.bundle)
        let base = b?.base ?? "Ubuntu 24.04 LTS"
        let logoPath = b?.logo ?? ""
        let logoHTML = (!logoPath.isEmpty && FileManager.default.fileExists(atPath: rootURL("web" + logoPath).path))
            ? "<img src=\"\(esc(logoPath))\" alt=\"\">" : (b?.icon ?? "🐧")

        let mon = Config.shared["GRAFANA_SUBDOMAIN"], dom = Config.shared["DOMAIN"]
        let monHref = (!mon.isEmpty && !dom.isEmpty) ? "https://\(esc(mon)).\(esc(dom))" : "#"

        // SSH by domain (Cloudflare tunnel) — never expose an IP to tenants.
        let sshHost = v.ssh_host ?? ""
        let ssh = sshHost.isEmpty ? "ssh admin@\(v.ip)" : "ssh admin@\(sshHost)"
        // one-time tenant setup (only meaningful once the VPS has a domain route)
        let sshSetup = sshHost.isEmpty ? "" : """
        <label class="fld">First time only — on your machine</label>
        <p class="hint sub2">Install <a href="https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" target="_blank">cloudflared</a>, then add this to <code>~/.ssh/config</code> so SSH tunnels through the domain (no IP, no open port):</p>
        <div class="copybox"><code id="sshcfg">Host *.\(esc(dom))\n  ProxyCommand cloudflared access ssh --hostname %h</code><button class="btn line" type="button" onclick="copyEl('sshcfg', this)">Copy</button></div>
        """

        // web terminal only makes sense on a running VM (ssh to a stopped one just fails).
        let running = v.status == "running"
        // no inline onclick — app/inline JS binds a click listener so it works after the poller
        // enables the button on starting→running (disabled just blocks clicks while booting).
        let webTerm = "<button class=\"btn\" id=\"termBtn\" type=\"button\"\(running ? "" : " disabled title=\"Start the server first\"")>▸ Web terminal</button>"
        let stopped = v.status == "stopped"

        return tpl("vps.html", [
            "NAME": esc(v.name),
            "DISPLAY": esc(v.display),
            "LABEL": esc(v.label ?? ""),
            "STATUS": esc(v.status),
            "STATUSCLASS": statusClass(v.status),
            "BUNDLE": esc(v.bundle),
            "BASE": esc(base),
            "LOGO": logoHTML,
            "CODE": esc(b?.code ?? ""),
            "CPU": String(v.cpu), "MEM": gb(v.mem_mb), "DISK": String(v.disk_gb),
            "IP": esc(v.ip),
            "SSHHOST": sshHost.isEmpty ? "<span class=\"muted\">— set Cloudflare keys in .env —</span>" : esc(sshHost),
            "SSH": esc(ssh),
            "SSHSETUP": sshSetup,
            "CREATED": esc(v.created),
            "WEBTERM": webTerm,
            // manual controls: Start only when stopped; Restart + Stop only when not stopped.
            "STARTHIDE": stopped ? "" : "hidden",
            "STOPHIDE":  stopped ? "hidden" : "",
            "RESTHIDE":  stopped ? "hidden" : "",
            "MONHREF": monHref,
            "CSRF": esc(csrf),
            "NOTICE": notice.map { "<div class=\"notice\">\(esc($0))</div>" } ?? "",
        ])
    }
}
