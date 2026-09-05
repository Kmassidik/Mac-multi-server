import Foundation
import CPTY

/// Bridges one browser terminal to one VPS: spawns `ssh` inside a real pty and
/// pipes bytes both ways. The panel runs ON the Mac, so it reaches the VPS
/// directly over the Tart bridge (192.168.64.x) with the host's ssh key —
/// no jump host needed. One PTYBridge per WebSocket connection.
final class PTYBridge {
    private let ip: String
    private let identity: String
    private var master: Int32 = -1
    private var proc: Process?
    private let q = DispatchQueue(label: "pty.reader")
    private var running = false

    init(ip: String) {
        self.ip = ip
        self.identity = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh/id_ed25519")
    }

    /// Spawn ssh in a pty. `onOutput` gets raw bytes as the VPS produces them;
    /// `onClose` fires once when the session ends (ssh exits or the pty closes).
    func start(cols: Int, rows: Int, onOutput: @escaping ([UInt8]) -> Void, onClose: @escaping () -> Void) {
        var m: Int32 = 0, s: Int32 = 0
        guard cpty_openpty(&m, &s, UInt16(max(1, min(rows, 300))), UInt16(max(1, min(cols, 500)))) == 0 else {
            onClose(); return
        }
        master = m
        let slave = FileHandle(fileDescriptor: s, closeOnDealloc: false)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = [
            "-tt",
            "-i", identity,
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes",           // key-only; never hang on a password prompt
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=20",
            "admin@\(ip)",
        ]
        p.standardInput = slave
        p.standardOutput = slave
        p.standardError = slave
        var closed = false
        let fireClose = { if !closed { closed = true; onClose() } }
        p.terminationHandler = { [weak self] _ in self?.stop(); fireClose() }

        do { try p.run() } catch {
            close(m); close(s); master = -1; fireClose(); return
        }
        proc = p
        close(s)                      // the child owns the slave now
        running = true

        q.async { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 16384)
            while self.running {
                let n = read(self.master, &buf, buf.count)
                if n <= 0 { break }
                onOutput(Array(buf[0..<n]))
            }
            self.stop(); fireClose()
        }
    }

    /// Forward keystrokes / paste from the browser to the VPS.
    func write(_ bytes: [UInt8]) {
        guard master >= 0, !bytes.isEmpty else { return }
        bytes.withUnsafeBytes { _ = Foundation.write(master, $0.baseAddress, bytes.count) }
    }

    func resize(cols: Int, rows: Int) {
        guard master >= 0 else { return }
        _ = cpty_setsize(master, UInt16(max(1, min(rows, 300))), UInt16(max(1, min(cols, 500))))
    }

    func stop() {
        running = false
        if let p = proc, p.isRunning { p.terminate() }
        proc = nil
        if master >= 0 { close(master); master = -1 }
    }
}
