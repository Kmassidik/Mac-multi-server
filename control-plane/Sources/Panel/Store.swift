import Foundation

/// Where the repo lives (launchd sets WorkingDirectory to the repo root).
let ROOT = FileManager.default.currentDirectoryPath
func rootURL(_ p: String) -> URL { URL(fileURLWithPath: ROOT).appendingPathComponent(p) }

/// Minimal .env reader (for display defaults like admin user / ssh jump).
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
            if let hash = v.firstIndex(of: "#") { v = String(v[..<hash]) }        // strip trailing comment
            kv[k] = v.trimmingCharacters(in: .whitespaces)
        }
    }
    subscript(_ k: String) -> String { kv[k] ?? "" }
}

/// One VPS, as written to state/<name>.json by deploy-vps.sh.
struct VPS: Codable {
    var name: String
    var bundle: String
    var status: String
    var cpu: Int
    var mem_mb: Int
    var disk_gb: Int
    var ip: String
    var app_port: String
    var hostname: String
    var created: String
}

enum Store {
    static var stateDir: URL { rootURL("state") }

    static func list() -> [VPS] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: stateDir,
                includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("vps-") }
            .compactMap { try? JSONDecoder().decode(VPS.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    /// Validate a VPS name to prevent any shell/path injection.
    static func validName(_ s: String) -> Bool {
        !s.isEmpty && s.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil
    }

    /// Kick off a deploy in the background (deploy takes ~60s). Returns immediately.
    static func deploy(bundle: String, cpu: Int, mem: Int, disk: Int) {
        // whitelist the bundle; clamp numbers — never trust the form blindly.
        let allowed = Set((Config.shared["BUNDLES"].isEmpty ? "blank,openclaw" : Config.shared["BUNDLES"])
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let b = allowed.contains(bundle) ? bundle : "blank"
        let args = ["--bundle", b,
                    "--cpu", String(max(1, min(cpu, 16))),
                    "--mem", String(max(512, min(mem, 131072))),
                    "--disk", String(max(10, min(disk, 500)))]
        run(script: "scripts/deploy-vps.sh", args: args, wait: false)
    }

    static func destroy(name: String) {
        guard validName(name) else { return }
        run(script: "scripts/destroy-vps.sh", args: [name], wait: false)
    }

    @discardableResult
    static func run(script: String, args: [String], wait: Bool) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [rootURL(script).path] + args
        p.currentDirectoryURL = URL(fileURLWithPath: ROOT)
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return "failed to launch \(script): \(error)" }
        if wait {
            p.waitUntilExit()
            let d = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: d, encoding: .utf8) ?? ""
        }
        return ""
    }
}
