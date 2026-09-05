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
        for (k, v) in vars { s = s.replacingOccurrences(of: "{{\(k)}}", with: v) }
        return s.replacingOccurrences(of: "\\{\\{[A-Z_]+\\}\\}", with: "", options: .regularExpression)
    }

    static func errBlock(_ e: String?) -> String { e.map { "<div class=\"err\">\(esc($0))</div>" } ?? "" }

    static func setup(error: String?, csrf: String) -> String {
        tpl("setup.html", ["ERROR": errBlock(error), "CSRF": esc(csrf),
                           "USER": esc(Config.shared.or("PANEL_ADMIN_USER", "admin"))])
    }

    static func login(error: String?, csrf: String) -> String {
        tpl("login.html", ["ERROR": errBlock(error), "CSRF": esc(csrf)])
    }

    static func dashboard(user: String, vpsList: [VPS], csrf: String, notice: String?) -> String {
        let jump = Config.shared["PANEL_SSH_JUMP"]
        let bl = Store.bundles()
        let firstKey = bl.first?.key ?? "blank"

        let bundles = bl.enumerated().map { (i, b) in """
            <div class="bcard\(i == 0 ? " sel" : "")" data-key="\(esc(b.key))" role="radio" aria-checked="\(i == 0)" tabindex="0">
              <div class="rdo"></div><div class="ico">\(b.icon)</div>
              <div class="bn">\(esc(b.name))</div><div class="bd">\(esc(b.description))</div>
            </div>
            """ }.joined()

        let mon = Config.shared["GRAFANA_SUBDOMAIN"], dom = Config.shared["DOMAIN"]
        let monLink = (!mon.isEmpty && !dom.isEmpty)
            ? " · <a href=\"https://\(esc(mon)).\(esc(dom))\" target=\"_blank\">monitoring</a>" : ""

        let servers = vpsList.isEmpty
            ? "<div class=\"vps empty\">No servers yet — deploy one above.</div>"
            : vpsList.map { v in
                let tag = v.status == "running" ? "tag run" : (v.status == "deploying" ? "tag dep" : "tag")
                let host = v.hostname.isEmpty ? "" : "<div class=\"kv\"><b>Host</b> <a href=\"https://\(esc(v.hostname))\" target=\"_blank\">\(esc(v.hostname))</a></div>"
                let ssh = "ssh -J \(jump.isEmpty ? "&lt;mac&gt;" : esc(jump)) admin@\(esc(v.ip))"
                return """
                <div class="vps">
                  <div class="top"><b>\(esc(v.name))</b><span class="\(tag)">\(esc(v.status))</span></div>
                  <div class="kv" style="color:var(--muted)">Ubuntu · \(v.cpu) vCPU · \(v.mem_mb) MB · \(v.disk_gb) GB · \(esc(v.bundle))</div>
                  <div class="kv"><b>IP</b> <code>\(esc(v.ip))</code></div>
                  \(host)
                  <div class="kv"><b>SSH</b> <code>\(ssh)</code></div>
                  <form method="post" action="/destroy" onsubmit="return confirm('Destroy \(esc(v.name))? This is permanent.')" style="margin-top:12px">
                    <input type="hidden" name="csrf" value="\(csrf)"><input type="hidden" name="name" value="\(esc(v.name))">
                    <button class="btn danger" type="submit">Destroy</button>
                  </form>
                </div>
                """
            }.joined()

        return tpl("dashboard.html", [
            "USER": esc(user), "MONLINK": monLink, "CSRF": esc(csrf),
            "NOTICE": notice.map { "<div class=\"notice\">\(esc($0))</div>" } ?? "",
            "BUNDLES": bundles, "FIRSTBUNDLE": esc(firstKey),
            "CPU": esc(Config.shared.or("VPS_DEFAULT_CPU", "2")),
            "MEM": esc(Config.shared.or("VPS_DEFAULT_MEM_MB", "4096")),
            "DISK": esc(Config.shared.or("VPS_DEFAULT_DISK_GB", "40")),
            "SERVERS": servers,
        ])
    }
}
