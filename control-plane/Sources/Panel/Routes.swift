import Foundation
import Swifter

/// JSON shapes the UI polls. `cls` is the status→CSS-class, computed server-side so the mapping
/// isn't duplicated in JavaScript.
struct StatusDTO: Encodable { let status: String; let cls: String }
struct VPSRowDTO: Encodable { let name: String; let status: String; let cls: String }

/// Sessions + per-IP login rate-limiting. Thread-safe.
///
/// Tokens carry an expiry and are persisted to `state/panel-sessions.json` (0600), so a panel
/// restart or crash (launchd relaunches it) doesn't log everyone out — the session survives —
/// while a bounded TTL still expires stale/stolen cookies. Rate-limit state stays in-memory
/// (short-lived by design). Falls back to memory-only if the file can't be written.
final class Sessions {
    static let ttl: TimeInterval = 7 * 24 * 3600   // 7 days

    private var tokens: [String: Date] = [:]        // token → expiry
    private var fails: [String: (n: Int, at: Date)] = [:]
    private let q = DispatchQueue(label: "panel.sessions")
    private let file: URL?

    init(file: URL? = nil) {
        self.file = file
        if let file, let d = try? Data(contentsOf: file),
           let raw = try? JSONDecoder().decode([String: Double].self, from: d) {
            let now = Date()
            for (t, exp) in raw where exp > now.timeIntervalSince1970 {
                tokens[t] = Date(timeIntervalSince1970: exp)
            }
        }
    }

    // caller must hold `q`. Writes the live (unexpired) token set to disk, 0600.
    private func persist() {
        guard let file else { return }
        let now = Date()
        let live = tokens.filter { $0.value > now }.mapValues { $0.timeIntervalSince1970 }
        guard let d = try? JSONEncoder().encode(live) else { return }
        try? d.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func new() -> String {
        let t = (0..<32).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        q.sync { tokens[t] = Date().addingTimeInterval(Self.ttl); persist() }
        return t
    }
    func valid(_ t: String?) -> Bool {
        guard let t else { return false }
        return q.sync {
            guard let exp = tokens[t] else { return false }
            if exp <= Date() { tokens[t] = nil; persist(); return false }   // expired → forget it
            return true
        }
    }
    func drop(_ t: String?)  { guard let t else { return }; q.sync { tokens[t] = nil; persist() } }
    func lockedOut(_ ip: String) -> Bool {
        q.sync {
            guard let f = fails[ip] else { return false }
            if Date().timeIntervalSince(f.at) > 300 { fails[ip] = nil; return false }   // 5-min window
            return f.n >= 5
        }
    }
    func recordFail(_ ip: String) { q.sync { fails[ip] = ((fails[ip]?.n ?? 0) + 1, Date()) } }
    func clearFail(_ ip: String)  { q.sync { fails[ip] = nil } }
}

private let COOKIE = "mms_session"
private func token(_ req: HttpRequest) -> String? {
    guard let cookie = req.headers["cookie"] else { return nil }
    for part in cookie.split(separator: ";") {
        let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
        if kv.count == 2, kv[0] == COOKIE { return String(kv[1]) }
    }
    return nil
}
private func form(_ req: HttpRequest) -> [String: String] {
    Dictionary(req.parseUrlencodedForm(), uniquingKeysWith: { a, _ in a })
}
private func redirect(_ to: String, cookie: String? = nil) -> HttpResponse {
    var h = ["Location": to]; if let c = cookie { h["Set-Cookie"] = c }
    return .raw(302, "Found", h) { _ in }
}
private func setCookie(_ t: String) -> String {
    // scope to .$DOMAIN so one login covers panel.$DOMAIN AND monitor.$DOMAIN
    let dom = Config.shared["DOMAIN"]
    let domainAttr = dom.isEmpty ? "" : " Domain=.\(dom);"
    return "\(COOKIE)=\(t); HttpOnly; Secure; Path=/;\(domainAttr) SameSite=Lax"
}
private func html(_ s: String) -> HttpResponse { .ok(.html(s)) }

/// Real client IP — behind cloudflared the socket peer is always 127.0.0.1, so trust the
/// forwarded headers first (Cloudflare sets CF-Connecting-IP).
private func clientIP(_ req: HttpRequest) -> String {
    if let cf = req.headers["cf-connecting-ip"], !cf.isEmpty { return cf }
    if let xff = req.headers["x-forwarded-for"], !xff.isEmpty {
        return xff.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? String(xff)
    }
    return req.address ?? "?"
}

// pre-auth CSRF (double-submit cookie) for the login/setup forms
private func randomToken() -> String { (0..<24).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined() }
private func csrfCookie(_ t: String) -> String { "mms_csrf=\(t); HttpOnly; Secure; Path=/; SameSite=Strict" }
private func csrfVal(_ req: HttpRequest) -> String? {
    guard let cookie = req.headers["cookie"] else { return nil }
    for part in cookie.split(separator: ";") {
        let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
        if kv.count == 2, kv[0] == "mms_csrf" { return String(kv[1]) }
    }
    return nil
}
/// clear the session cookie — must mirror the Domain it was set with, or the browser keeps it.
private func clearCookie() -> String {
    let dom = Config.shared["DOMAIN"]
    let d = dom.isEmpty ? "" : " Domain=.\(dom);"
    return "\(COOKIE)=; HttpOnly; Secure; Path=/;\(d) Max-Age=0"
}

/// Wire all routes. Keeps main.swift tiny.
func installRoutes(on server: HttpServer, auth: Auth, sessions: Sessions) {
    func authed(_ r: HttpRequest) -> Bool { sessions.valid(token(r)) }
    func csrfOK(_ r: HttpRequest) -> Bool { guard let t = token(r) else { return false }; return form(r)["csrf"] == t }

    // serve login/setup with a fresh CSRF cookie (double-submit pattern)
    func serveAuth(login: Bool, error: String?) -> HttpResponse {
        let t = randomToken()
        let page = login ? Pages.login(error: error, csrf: t) : Pages.setup(error: error, csrf: t)
        return .raw(200, "OK", ["Content-Type": "text/html; charset=utf-8", "Set-Cookie": csrfCookie(t)]) {
            try $0.write([UInt8](page.utf8))
        }
    }
    func csrfFormOK(_ req: HttpRequest) -> Bool { guard let c = csrfVal(req), !c.isEmpty else { return false }; return form(req)["csrf"] == c }

    // Anti-CSWSH: if a browser Origin is present it must be our panel host (or localhost).
    // (SameSite=Lax already blocks the session cookie on cross-site WS; this is belt-and-braces.)
    func originOK(_ req: HttpRequest) -> Bool {
        guard let origin = req.headers["origin"], !origin.isEmpty else { return true }  // non-browser client
        let dom = Config.shared["DOMAIN"], panel = Config.shared.or("PANEL_SUBDOMAIN", "panel")
        if !dom.isEmpty, origin == "https://\(panel).\(dom)" { return true }
        // localhost dev only — parse the host so "127.0.0.1.evil.com" can't slip a prefix match
        if let host = URL(string: origin)?.host { return host == "127.0.0.1" || host == "localhost" }
        return false
    }

    // Monitoring (Beszel) has its own login and is routed straight to its hub by cloudflared,
    // so the panel doesn't proxy it — nothing to intercept here.

    func dashPage(_ req: HttpRequest) -> HttpResponse {
        guard auth.isConfigured, authed(req) else { return redirect("/") }   // protected → bounce to login
        let notice = (req.queryParams.first(where: { $0.0 == "notice" })?.1).flatMap { $0.removingPercentEncoding ?? $0 }
        return html(Pages.dashboard(user: auth.username() ?? "admin",
                                    vpsList: Store.list(), csrf: token(req) ?? "", notice: notice))
    }
    server.GET["/"] = { req in
        if auth.isConfigured && authed(req) { return redirect("/dashboard") }
        return serveAuth(login: auth.isConfigured, error: nil)
    }
    server.GET["/dashboard"] = { req in dashPage(req) }

    // static assets from web/
    func staticFile(_ rel: String, _ ctype: String) -> HttpResponse {
        guard let d = try? Data(contentsOf: rootURL("web/\(rel)")) else { return .notFound }
        return .raw(200, "OK", ["Content-Type": ctype, "Cache-Control": "no-cache"]) { try $0.write([UInt8](d)) }
    }
    server.GET["/style.css"] = { _ in staticFile("style.css", "text/css; charset=utf-8") }
    server.GET["/app.js"]   = { _ in staticFile("app.js", "application/javascript; charset=utf-8") }
    // bundle logos (served locally, not hotlinked). Basename only — no path traversal.
    server.GET["/logos/:file"] = { req in
        let f = req.params[":file"] ?? ""
        guard f.range(of: "^[A-Za-z0-9_-]+\\.(svg|png|webp|jpg|jpeg)$", options: .regularExpression) != nil else { return .notFound }
        let ctype: String
        switch (f as NSString).pathExtension.lowercased() {
        case "svg":         ctype = "image/svg+xml"
        case "png":         ctype = "image/png"
        case "webp":        ctype = "image/webp"
        case "jpg","jpeg":  ctype = "image/jpeg"
        default:            ctype = "application/octet-stream"
        }
        return staticFile("logos/\(f)", ctype)
    }
    // vendored front-end libs (xterm.js) — self-hosted, basename only.
    server.GET["/vendor/:file"] = { req in
        let f = req.params[":file"] ?? ""
        guard f.range(of: "^[A-Za-z0-9._-]+\\.(js|css|map)$", options: .regularExpression) != nil else { return .notFound }
        let ctype = f.hasSuffix(".css") ? "text/css; charset=utf-8" : "application/javascript; charset=utf-8"
        return staticFile("vendor/\(f)", ctype)
    }

    // ── VPS detail page ──────────────────────────────────────────────
    server.GET["/vps/:name"] = { req in
        guard auth.isConfigured, authed(req) else { return redirect("/") }
        guard let v = Store.get(req.params[":name"] ?? "") else { return redirect("/dashboard?notice=No%20such%20VPS") }
        let notice = (req.queryParams.first(where: { $0.0 == "notice" })?.1).flatMap { $0.removingPercentEncoding ?? $0 }
        return html(Pages.vpsDetail(vps: v, csrf: token(req) ?? "", notice: notice))
    }
    // JSON responses — polled by the UI so stop/start/restart reflect without a refresh.
    // Encoded (not hand-built) so there's no escaping to get wrong; `cls` is computed once here
    // (Pages.statusClass) and sent to the client, so the status→CSS-class mapping lives in ONE place.
    func jsonOK(_ s: String) -> HttpResponse {          // for pre-built JSON strings (Beszel proxy)
        .raw(200, "OK", ["Content-Type": "application/json", "Cache-Control": "no-store"]) { try $0.write([UInt8](s.utf8)) }
    }
    func jsonEncode<T: Encodable>(_ v: T) -> HttpResponse {
        let data = (try? JSONEncoder().encode(v)) ?? Data("null".utf8)
        return .raw(200, "OK", ["Content-Type": "application/json", "Cache-Control": "no-store"]) { try $0.write([UInt8](data)) }
    }
    server.GET["/vps/:name/status"] = { req in
        guard authed(req) else { return .raw(401, "Unauthorized", nil) { _ in } }
        guard let v = Store.get(req.params[":name"] ?? "") else { return .notFound }
        return jsonEncode(StatusDTO(status: v.status, cls: Pages.statusClass(v.status)))
    }
    server.GET["/api/vps"] = { req in
        guard authed(req) else { return .raw(401, "Unauthorized", nil) { _ in } }
        return jsonEncode(Store.list().map { VPSRowDTO(name: $0.name, status: $0.status, cls: Pages.statusClass($0.status)) })
    }
    // live metrics for the Monitoring tab (panel proxies the Beszel hub, matched by VM IP)
    server.GET["/vps/:name/metrics"] = { req in
        guard authed(req) else { return .raw(401, "Unauthorized", nil) { _ in } }
        guard let v = Store.get(req.params[":name"] ?? ""), !v.ip.isEmpty else { return .notFound }
        return jsonOK(Beszel.metricsJSON(ip: v.ip, vps: v.status))
    }

    // rename the human "Name" tag
    server.POST["/vps/:name/rename"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        let name = req.params[":name"] ?? ""
        guard Store.get(name) != nil else { return redirect("/dashboard") }
        Store.rename(name, label: form(req)["label"] ?? "")
        return redirect("/vps/\(name)?notice=Renamed")
    }

    // manual lifecycle controls — restart / stop / start (same engine as `mms`)
    server.POST["/vps/:name/restart"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        let name = req.params[":name"] ?? ""
        guard Store.get(name) != nil else { return redirect("/dashboard") }
        Store.restart(name: name)
        return redirect("/vps/\(name)?notice=Restarting%E2%80%A6")
    }
    server.POST["/vps/:name/stop"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        let name = req.params[":name"] ?? ""
        guard Store.get(name) != nil else { return redirect("/dashboard") }
        Store.stop(name: name)
        return redirect("/vps/\(name)?notice=Stopping%E2%80%A6")
    }
    server.POST["/vps/:name/start"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        let name = req.params[":name"] ?? ""
        guard Store.get(name) != nil else { return redirect("/dashboard") }
        Store.start(name: name)
        return redirect("/vps/\(name)?notice=Starting%E2%80%A6")
    }

    // ── Web terminal: browser ⇄ (this WebSocket) ⇄ ssh-in-a-pty ⇄ VPS ──
    // One PTYBridge per connection. Auth via the session cookie; Origin-checked.
    server["/vps/:name/term"] = { req -> HttpResponse in
        guard auth.isConfigured, authed(req), originOK(req) else { return .raw(403, "Forbidden", nil) { _ in } }
        guard let v = Store.get(req.params[":name"] ?? ""), !v.ip.isEmpty else { return .notFound }
        let pty = PTYBridge(ip: v.ip)
        return websocket(
            text: { _, txt in
                // control channel: {"resize":[cols,rows]}
                if let d = txt.data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let r = o["resize"] as? [Int], r.count == 2 {
                    pty.resize(cols: r[0], rows: r[1])
                }
            },
            binary: { _, bytes in pty.write(bytes) },       // keystrokes / paste
            connected: { session in
                pty.start(cols: 80, rows: 24,
                    onOutput: { session.writeBinary($0) },
                    onClose: {
                        session.writeText("\r\n\u{1b}[90m— session closed —\u{1b}[0m\r\n")
                        session.writeFrame(ArraySlice<UInt8>(), .close)
                    })
            },
            disconnected: { _ in pty.stop() }
        )(req)
    }

    server.POST["/setup"] = { req in
        guard !auth.isConfigured else { return redirect("/") }
        guard csrfFormOK(req) else { return serveAuth(login: false, error: "Session expired — try again.") }
        let f = form(req); let u = f["username"] ?? "", p = f["password"] ?? "", c = f["confirm"] ?? ""
        guard !u.isEmpty, p.count >= 8, p == c else { return serveAuth(login: false, error: "Password must be ≥8 chars and match.") }
        do { try auth.set(username: u, password: p) } catch { return serveAuth(login: false, error: "Could not save: \(error)") }
        return redirect("/dashboard", cookie: setCookie(sessions.new()))
    }

    server.POST["/login"] = { req in
        let ip = clientIP(req)
        if sessions.lockedOut(ip) { return serveAuth(login: true, error: "Too many attempts. Wait a few minutes.") }
        guard csrfFormOK(req) else { return serveAuth(login: true, error: "Session expired — try again.") }
        let f = form(req)
        if auth.verify(username: f["username"] ?? "", password: f["password"] ?? "") {
            sessions.clearFail(ip); return redirect("/dashboard", cookie: setCookie(sessions.new()))
        }
        sessions.recordFail(ip); usleep(400_000)
        return serveAuth(login: true, error: "Invalid username or password")
    }

    server.POST["/logout"] = { req in
        if csrfOK(req) { sessions.drop(token(req)) }
        return redirect("/", cookie: clearCookie())
    }

    server.POST["/deploy"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        let f = form(req)
        Store.deploy(bundle: f["bundle"] ?? "blank",
                     cpu:  Int(f["cpu"]  ?? "") ?? 2,
                     mem:  Int(f["mem"]  ?? "") ?? 4096,
                     disk: Int(f["disk"] ?? "") ?? 40,
                     label: f["label"] ?? "")
        return redirect("/dashboard")   // the new VPS shows up as a live "provisioning" flag
    }

    server.POST["/destroy"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        Store.destroy(name: form(req)["name"] ?? "")
        return redirect("/dashboard?notice=Destroying%20VPS%E2%80%A6")
    }
}
