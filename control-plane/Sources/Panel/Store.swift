import Foundation

/// One VPS, as written to state/<name>.json by `mms deploy`.
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

/// Reads VPS state and drives the `mms` CLI. The panel never re-implements the
/// engine — it calls the same command you'd run by hand.
/// A deploy bundle, from templates/<key>/meta.json.
struct Bundle {
    var key: String
    var name: String
    var code: String
    var icon: String
    var logo: String      // URL path like /logos/x.svg; used only if the file exists (else icon)
    var description: String
}

enum Store {
    static var stateDir: URL { rootURL("state") }

    /// Bundles offered at deploy time — the BUNDLES list in .env, enriched from each
    /// templates/<key>/meta.json (name, icon, description).
    static func bundles() -> [Bundle] {
        let keys = Config.shared.or("BUNDLES", "blank,openclaw,hermes")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return keys.map { key in
            let meta = (try? Data(contentsOf: rootURL("templates/\(key)/meta.json")))
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            return Bundle(key: key,
                          name: meta["name"] ?? key.capitalized,
                          code: meta["code"] ?? key.uppercased(),
                          icon: meta["icon"] ?? "📦",
                          logo: meta["logo"] ?? "",
                          description: meta["description"] ?? "")
        }
    }

    static func list() -> [VPS] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: stateDir,
                includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("vps-") }
            .compactMap { try? JSONDecoder().decode(VPS.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    static func validName(_ s: String) -> Bool {
        !s.isEmpty && s.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil
    }

    /// Kick off a deploy (takes ~60s) in the background — never trust the form blindly.
    static func deploy(bundle: String, cpu: Int, mem: Int, disk: Int) {
        let allowed = Set(Config.shared.or("BUNDLES", "blank,openclaw")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let b = allowed.contains(bundle) ? bundle : "blank"
        mms(["deploy", "--bundle", b,
             "--cpu",  String(max(1, min(cpu, 16))),
             "--mem",  String(max(512, min(mem, 131072))),
             "--disk", String(max(10, min(disk, 500)))])
    }

    static func destroy(name: String) {
        guard validName(name) else { return }
        mms(["destroy", name])
    }

    /// Run `./mms <args>` from the repo root, detached.
    private static func mms(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [rootURL("mms").path] + args
        p.currentDirectoryURL = URL(fileURLWithPath: ROOT)
        let label = args.joined(separator: "-").replacingOccurrences(of: "--", with: "")
        let logPath = "/tmp/mms-\(label).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let logh = FileHandle(forWritingAtPath: logPath) ?? .nullDevice
        p.standardOutput = logh
        p.standardError = logh
        try? p.run()   // fire-and-forget; state file appears when done
    }
}
