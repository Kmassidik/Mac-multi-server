import Foundation
import Swifter

// macserver-panel — native Swift control plane for Mac-multi-server.
// Login + dashboard, binds localhost, exposed only via Cloudflare.

func argValue(_ flag: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: flag), i + 1 < a.count { return a[i + 1] }
    return nil
}

let port = UInt16(argValue("--port") ?? Config.shared["PANEL_PORT"]) ?? 8088
let bind = "127.0.0.1"                    // never exposed directly; reach it via Cloudflare
let auth = Auth(dir: rootURL("state"))
let sessions = Sessions()

let server = HttpServer()
server.listenAddressIPv4 = bind
installRoutes(on: server, auth: auth, sessions: sessions)

print("Mac-multi-server panel → http://\(bind):\(port)  (localhost only; expose via Cloudflare)")
if !auth.isConfigured { print("  first run: open the panel to create the admin login") }

do {
    try server.start(port, forceIPv4: true)
    RunLoop.main.run()
} catch {
    FileHandle.standardError.write(Data("failed to start on \(bind):\(port) — \(error)\n".utf8))
    exit(1)
}
