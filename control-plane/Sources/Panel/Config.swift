import Foundation

/// Repo root — launchd sets WorkingDirectory to it; falls back to cwd.
let ROOT = FileManager.default.currentDirectoryPath
func rootURL(_ p: String) -> URL { URL(fileURLWithPath: ROOT).appendingPathComponent(p) }

/// Cache-busting token for static assets — new value each process start (i.e. each deploy),
/// so ?v=ASSET_VER forces browsers/Cloudflare to fetch the fresh style.css / app.js.
let ASSET_VER = String(Int(Date().timeIntervalSince1970))

/// Minimal `.env` reader (display defaults: admin user, ssh jump, domain…).
struct Config {
    static let shared = Config()
    private var kv: [String: String] = [:]

    init() {
        guard let text = try? String(contentsOf: rootURL(".env"), encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            let k = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
            var v = String(s[s.index(after: eq)...])
            if let hash = v.firstIndex(of: "#") { v = String(v[..<hash]) }   // strip trailing comment
            kv[k] = v.trimmingCharacters(in: .whitespaces)
        }
    }

    subscript(_ k: String) -> String { kv[k] ?? "" }
    /// value or a fallback if empty/missing
    func or(_ k: String, _ fallback: String) -> String { let v = self[k]; return v.isEmpty ? fallback : v }
}
