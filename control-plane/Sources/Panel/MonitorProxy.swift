import Foundation
import Swifter

// Monitoring behind the panel's login (Option 1: one door for everything).
//
// cloudflared routes BOTH panel.$DOMAIN and monitor.$DOMAIN to this same panel binary.
// A request whose Host is monitor.$DOMAIN is gated by the panel session, then reverse-proxied
// to the local Netdata agent (127.0.0.1:19999). Root-to-root proxying keeps Netdata's absolute
// asset paths working. The session cookie is scoped to .$DOMAIN so one login covers both subdomains.

let NETDATA_ORIGIN = "http://127.0.0.1:19999"

/// The monitor hostname the panel should intercept, e.g. "monitor.kurniatech.my.id".
func monitorHost() -> String {
    let sub = Config.shared.or("GRAFANA_SUBDOMAIN", "monitor")
    let dom = Config.shared["DOMAIN"]
    return dom.isEmpty ? "" : "\(sub).\(dom)"
}

private func netdataURL(for req: HttpRequest) -> URL? {
    var path = req.path
    if !req.queryParams.isEmpty {
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        path += "?" + req.queryParams.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
    }
    return URL(string: NETDATA_ORIGIN + path)
}

/// Reverse-proxy one request to Netdata (synchronous — Swifter handlers are sync).
func proxyNetdata(_ req: HttpRequest) -> HttpResponse {
    guard let url = netdataURL(for: req) else { return .internalServerError }
    var r = URLRequest(url: url)
    r.httpMethod = req.method
    r.timeoutInterval = 30
    let skip: Set<String> = ["host", "connection", "content-length", "accept-encoding"]
    for (k, v) in req.headers where !skip.contains(k.lowercased()) { r.setValue(v, forHTTPHeaderField: k) }
    if !req.body.isEmpty { r.httpBody = Data(req.body) }

    let sem = DispatchSemaphore(value: 0)
    var out: HttpResponse = .raw(502, "Bad Gateway", ["Content-Type": "text/plain"]) {
        try $0.write([UInt8]("monitoring backend (Netdata) not reachable".utf8))
    }
    URLSession.shared.dataTask(with: r) { data, resp, _ in
        defer { sem.signal() }
        guard let http = resp as? HTTPURLResponse else { return }
        var headers: [String: String] = [:]
        let drop: Set<String> = ["transfer-encoding", "content-encoding", "connection", "content-length"]
        for (k, v) in http.allHeaderFields {
            let ks = "\(k)".lowercased(); if drop.contains(ks) { continue }
            headers["\(k)"] = "\(v)"
        }
        let body = [UInt8](data ?? Data())
        out = .raw(http.statusCode, "OK", headers) { try $0.write(body) }
    }.resume()
    sem.wait()
    return out
}
