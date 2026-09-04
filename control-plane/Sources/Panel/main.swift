import Foundation
import Swifter

// ── config ───────────────────────────────────────────────────
func argValue(_ flag: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: flag), i + 1 < a.count { return a[i + 1] }
    return nil
}
let port = UInt16(argValue("--port") ?? Config.shared["PANEL_PORT"]) ?? 8088
let bind = "127.0.0.1"   // never exposed directly; reachable only via Cloudflare

// auth + sessions live in the repo's state/ dir (gitignored)
let auth = Auth(dir: rootURL("state"))

// ── session + rate-limit store (thread-safe) ─────────────────
final class Sessions {
    private var tokens = Set<String>()
    private var fails: [String: (n: Int, at: Date)] = [:]      // per-IP login failures
    private let q = DispatchQueue(label: "panel.sessions")
    func new() -> String {
        let t = (0..<32).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        q.sync { _ = tokens.insert(t) }; return t
    }
    func valid(_ t: String?) -> Bool { guard let t else { return false }; return q.sync { tokens.contains(t) } }
    func drop(_ t: String?) { guard let t else { return }; q.sync { _ = tokens.remove(t) } }
    /// returns true if this IP is currently locked out
    func lockedOut(_ ip: String) -> Bool {
        q.sync {
            guard let f = fails[ip] else { return false }
            if Date().timeIntervalSince(f.at) > 300 { fails[ip] = nil; return false }  // 5-min window
            return f.n >= 5
        }
    }
    func recordFail(_ ip: String) { q.sync { let f = fails[ip]; fails[ip] = ((f?.n ?? 0) + 1, Date()) } }
    func clearFail(_ ip: String) { q.sync { fails[ip] = nil } }
}
let sessions = Sessions()

// ── helpers ──────────────────────────────────────────────────
func cookieToken(_ req: HttpRequest) -> String? {
    guard let cookie = req.headers["cookie"] else { return nil }
    for part in cookie.split(separator: ";") {
        let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
        if kv.count == 2, kv[0] == "mms_session" { return String(kv[1]) }
    }
    return nil
}
func authed(_ req: HttpRequest) -> Bool { sessions.valid(cookieToken(req)) }
func form(_ req: HttpRequest) -> [String: String] {
    Dictionary(req.parseUrlencodedForm(), uniquingKeysWith: { a, _ in a })
}
func csrfOK(_ req: HttpRequest) -> Bool {
    guard let t = cookieToken(req) else { return false }
    return form(req)["csrf"] == t
}
func redirect(_ to: String, setCookie: String? = nil) -> HttpResponse {
    var h = ["Location": to]; if let c = setCookie { h["Set-Cookie"] = c }
    return .raw(302, "Found", h) { _ in }
}
func html(_ s: String) -> HttpResponse { .ok(.html(s)) }
func clientIP(_ req: HttpRequest) -> String { req.address ?? "?" }

// ── routes ───────────────────────────────────────────────────
let server = HttpServer()
server.listenAddressIPv4 = bind

server.GET["/"] = { req in
    if !auth.isConfigured { return html(Pages.setup(error: nil)) }
    guard authed(req) else { return html(Pages.login(error: nil)) }
    let notice = req.queryParams.first(where: { $0.0 == "notice" })?.1
    return html(Pages.dashboard(user: auth.username() ?? "admin",
                                vpsList: Store.list(),
                                csrf: cookieToken(req) ?? "",
                                notice: notice))
}

server.POST["/setup"] = { req in
    guard !auth.isConfigured else { return redirect("/") }
    let f = form(req)
    let u = f["username"] ?? "", p = f["password"] ?? "", c = f["confirm"] ?? ""
    guard u.count >= 1, p.count >= 8, p == c else {
        return html(Pages.setup(error: "Password must be ≥8 chars and match."))
    }
    do { try auth.set(username: u, password: p) } catch { return html(Pages.setup(error: "Could not save: \(error)")) }
    let t = sessions.new()
    return redirect("/", setCookie: "mms_session=\(t); HttpOnly; Secure; Path=/; SameSite=Lax")
}

server.POST["/login"] = { req in
    let ip = clientIP(req)
    if sessions.lockedOut(ip) { return html(Pages.login(error: "Too many attempts. Wait a few minutes.")) }
    let f = form(req)
    if auth.verify(username: f["username"] ?? "", password: f["password"] ?? "") {
        sessions.clearFail(ip)
        let t = sessions.new()
        return redirect("/", setCookie: "mms_session=\(t); HttpOnly; Secure; Path=/; SameSite=Lax")
    }
    sessions.recordFail(ip); usleep(400_000)
    return html(Pages.login(error: "Invalid username or password"))
}

server.POST["/logout"] = { req in
    if csrfOK(req) { sessions.drop(cookieToken(req)) }
    return redirect("/", setCookie: "mms_session=; Path=/; Max-Age=0")
}

server.POST["/deploy"] = { req in
    guard authed(req), csrfOK(req) else { return redirect("/") }
    let f = form(req)
    Store.deploy(bundle: f["bundle"] ?? "blank",
                 cpu: Int(f["cpu"] ?? "") ?? 2,
                 mem: Int(f["mem"] ?? "") ?? 4096,
                 disk: Int(f["disk"] ?? "") ?? 40)
    return redirect("/?notice=Deploying%20a%20new%20VPS%E2%80%A6%20it%20will%20appear%20in%20~1%20min%20%28refresh%29.")
}

server.POST["/destroy"] = { req in
    guard authed(req), csrfOK(req) else { return redirect("/") }
    Store.destroy(name: form(req)["name"] ?? "")
    return redirect("/?notice=Destroying%20VPS%E2%80%A6")
}

// ── go ───────────────────────────────────────────────────────
print("Mac-multi-server panel → http://\(bind):\(port)  (bound localhost; expose via Cloudflare)")
if !auth.isConfigured { print("  first run: open the panel to create the admin login") }
do {
    try server.start(port, forceIPv4: true)
    RunLoop.main.run()
} catch {
    FileHandle.standardError.write(Data("failed to start on \(bind):\(port) — \(error)\n".utf8))
    exit(1)
}
