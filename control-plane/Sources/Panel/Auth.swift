import Foundation
import CommonCrypto
import Security

/// Single admin credential, PBKDF2-HMAC-SHA256 hashed. Stored 0600.
/// (Adapted from vantis-agent's Auth — native CommonCrypto, no dependencies.)
struct Credentials: Codable {
    var username: String
    var salt: String        // base64
    var hash: String        // base64
    var iterations: Int
}

struct Auth {
    let file: URL
    init(dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.file = dir.appendingPathComponent("panel-auth.json")
    }

    var isConfigured: Bool { FileManager.default.fileExists(atPath: file.path) }

    func username() -> String? {
        guard let d = try? Data(contentsOf: file),
              let c = try? JSONDecoder().decode(Credentials.self, from: d) else { return nil }
        return c.username
    }

    func set(username: String, password: String) throws {
        let salt = Self.randomBytes(16)
        let iterations = 120_000
        let hash = Self.pbkdf2(password: password, salt: salt, iterations: iterations)
        let cred = Credentials(username: username,
                               salt: salt.base64EncodedString(),
                               hash: hash.base64EncodedString(),
                               iterations: iterations)
        try JSONEncoder().encode(cred).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func verify(username: String, password: String) -> Bool {
        guard let d = try? Data(contentsOf: file),
              let c = try? JSONDecoder().decode(Credentials.self, from: d),
              let salt = Data(base64Encoded: c.salt),
              let expected = Data(base64Encoded: c.hash),
              c.username == username else { return false }
        let got = Self.pbkdf2(password: password, salt: salt, iterations: c.iterations)
        return Self.constantTimeEqual(got, expected)
    }

    // MARK: crypto
    static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n)
        _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return d
    }
    static func pbkdf2(password: String, salt: Data, iterations: Int) -> Data {
        let pw = Array(password.utf8); let saltBytes = [UInt8](salt)
        var out = [UInt8](repeating: 0, count: 32)
        pw.withUnsafeBufferPointer { pwPtr in
            saltBytes.withUnsafeBufferPointer { saltPtr in
                pwPtr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pw.count) { pwChar in
                    _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwChar, pw.count,
                        saltPtr.baseAddress, saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        &out, out.count)
                }
            }
        }
        return Data(out)
    }
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0; for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
