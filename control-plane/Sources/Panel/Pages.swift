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

        // environment grid: real radios (name=bundle) — active state is pure CSS (input:checked + .envcard)
        let bundles = bl.enumerated().map { (i, b) in """
            <label>
              <input type="radio" name="bundle" value="\(esc(b.key))"\(i == 0 ? " checked" : "")>
              <div class="envcard">
                <div class="badge"></div>
                <span class="code">\(esc(b.code))</span>
                <h3>\(esc(b.name))</h3>
                <p>\(esc(b.description))</p>
              </div>
            </label>
            """ }.joined()

        let mon = Config.shared["GRAFANA_SUBDOMAIN"], dom = Config.shared["DOMAIN"]
        let monHref = (!mon.isEmpty && !dom.isEmpty) ? "https://\(esc(mon)).\(esc(dom))" : "#"
        let announce = dom.isEmpty ? "MAC-MULTI-SERVER · CONTROL PLANE" : "MAC-MULTI-SERVER · \(esc(dom.uppercased()))"

        let servers = vpsList.isEmpty
            ? "<div class=\"empty\">// NO INSTANCES PROVISIONED IN CURRENT CLUSTER</div>"
            : vpsList.map { v in
                let host = v.hostname.isEmpty ? "" : " · <a href=\"https://\(esc(v.hostname))\" target=\"_blank\">\(esc(v.hostname))</a>"
                let ssh = "ssh -J \(jump.isEmpty ? "&lt;mac&gt;" : esc(jump)) admin@\(esc(v.ip))"
                let tag = v.status == "running" ? "tag run" : "tag"
                return """
                <div class="vps">
                  <div class="id">
                    <div class="live"></div>
                    <div>
                      <div class="nm">\(esc(v.name))</div>
                      <div class="sub">\(esc(v.bundle)) · \(v.cpu) vCPU · \(v.mem_mb) MB · \(v.disk_gb) GB · \(esc(v.ip))\(host)</div>
                      <div class="sub">\(ssh)</div>
                    </div>
                  </div>
                  <div class="right">
                    <span class="\(tag)">\(esc(v.status))</span>
                    <form method="post" action="/destroy" onsubmit="return confirm('Destroy \(esc(v.name))? This is permanent.')">
                      <input type="hidden" name="csrf" value="\(csrf)"><input type="hidden" name="name" value="\(esc(v.name))">
                      <button class="btn line" type="submit">Terminate</button>
                    </form>
                  </div>
                </div>
                """
            }.joined()

        return tpl("dashboard.html", [
            "ANNOUNCE": announce, "USER": esc(user), "MONHREF": monHref, "CSRF": esc(csrf),
            "NOTICE": notice.map { "<div class=\"notice\">\(esc($0))</div>" } ?? "",
            "OPTCOUNT": String(bl.count), "COUNT": String(vpsList.count),
            "BUNDLES": bundles,
            "CPU": esc(Config.shared.or("VPS_DEFAULT_CPU", "2")),
            "MEM": esc(Config.shared.or("VPS_DEFAULT_MEM_MB", "4096")),
            "DISK": esc(Config.shared.or("VPS_DEFAULT_DISK_GB", "40")),
            "SERVERS": servers,
        ])
    }
}
