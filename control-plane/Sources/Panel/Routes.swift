import Foundation
import Swifter

/// In-memory sessions + per-IP login rate-limiting. Thread-safe.
final class Sessions {
    private var tokens = Set<String>()
    private var fails: [String: (n: Int, at: Date)] = [:]
    private let q = DispatchQueue(label: "panel.sessions")

    func new() -> String {
        let t = (0..<32).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        q.sync { _ = tokens.insert(t) }; return t
    }
    func valid(_ t: String?) -> Bool { guard let t else { return false }; return q.sync { tokens.contains(t) } }
    func drop(_ t: String?)  { guard let t else { return }; q.sync { _ = tokens.remove(t) } }
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
        return origin.hasPrefix("http://127.0.0.1") || origin.hasPrefix("http://localhost")
    }

    // Monitoring (Beszel) has its own login and is routed straight to its hub by cloudflared,
    // so the panel doesn't proxy it — nothing to intercept here.

    func dashPage(_ req: HttpRequest) -> HttpResponse {
        guard auth.isConfigured, authed(req) else { return redirect("/") }   // protected → bounce to login
        let notice = req.queryParams.first(where: { $0.0 == "notice" })?.1
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
        let notice = req.queryParams.first(where: { $0.0 == "notice" })?.1
        return html(Pages.vpsDetail(vps: v, csrf: token(req) ?? "", notice: notice))
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
        return redirect("/dashboard?notice=Deploying%20a%20new%20VPS%E2%80%A6%20refresh%20in%20~1%20min.")
    }

    server.POST["/destroy"] = { req in
        guard authed(req), csrfOK(req) else { return redirect("/") }
        Store.destroy(name: form(req)["name"] ?? "")
        return redirect("/dashboard?notice=Destroying%20VPS%E2%80%A6")
    }
}
