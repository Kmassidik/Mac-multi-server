import Foundation

/// Reads a VPS's current metrics from the local Beszel hub (which has its own login, so the
/// panel proxies it server-side using the admin creds in .env). Matched by the VM's IP, because
/// the agent registers under the guest hostname, not our vps-N name.
enum Beszel {
    static let hub = "http://127.0.0.1:8090"

    private static func send(_ url: URL, method: String, body: Data?, token: String?) -> Data? {
        var r = URLRequest(url: url, timeoutInterval: 4)
        r.httpMethod = method
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { r.setValue(token, forHTTPHeaderField: "Authorization") }
        let sem = DispatchSemaphore(value: 0); var out: Data?
        URLSession.shared.dataTask(with: r) { d, _, _ in out = d; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return out
    }

    private static func authToken() -> String? {
        let email = Config.shared["BESZEL_ADMIN_EMAIL"], pass = Config.shared["BESZEL_ADMIN_PASSWORD"]
        guard !email.isEmpty, !pass.isEmpty,
              let url = URL(string: "\(hub)/api/collections/_superusers/auth-with-password"),
              let body = try? JSONSerialization.data(withJSONObject: ["identity": email, "password": pass]),
              let d = send(url, method: "POST", body: body, token: nil),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o["token"] as? String
    }

    /// JSON for the Monitoring tab: {ok,vps,status,live,cpu,mem,disk,up} or {error:…}.
    /// `vps` is the panel's own state (authoritative for stopped); `status` is the Beszel agent
    /// status; `live` is true only when the agent is actually reporting (else numbers are stale).
    static func metricsJSON(ip: String, vps: String) -> String {
        func err(_ e: String) -> String { "{\"error\":\"\(e)\",\"vps\":\"\(vps)\"}" }
        guard !Config.shared["BESZEL_ADMIN_EMAIL"].isEmpty else { return err("not_configured") }
        guard let tok = authToken() else { return err("hub_unreachable") }
        var comps = URLComponents(string: "\(hub)/api/collections/systems/records")!
        comps.queryItems = [.init(name: "filter", value: "(host='\(ip)')"), .init(name: "perPage", value: "1")]
        guard let url = comps.url, let d = send(url, method: "GET", body: nil, token: tok),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let items = o["items"] as? [[String: Any]], let sys = items.first else { return err("no_agent") }
        let info = sys["info"] as? [String: Any] ?? [:]
        func n(_ k: String) -> Double { (info[k] as? Double) ?? Double((info[k] as? Int) ?? 0) }
        let bstatus = sys["status"] as? String ?? "?"
        // "live" only when the VPS is running AND the agent is up — otherwise the info is stale.
        let live = (vps == "running") && (bstatus == "up")
        let obj: [String: Any] = ["ok": true, "vps": vps, "status": bstatus, "live": live,
                                  "cpu": n("cpu"), "mem": n("mp"), "disk": n("dp"), "up": n("u")]
        return (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? err("parse")
    }
}
