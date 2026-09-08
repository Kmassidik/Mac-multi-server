// PanelCore — the panel's pure, I/O-free helpers, factored out so they can be unit-tested
// with a bare Swift toolchain (no Xcode/XCTest needed — the host is Command-Line-Tools only).
// The Panel executable re-exposes these through `Pages` so its call sites are unchanged.

import Foundation

public enum PanelCore {
    /// Escape the four HTML-significant characters. `&` first, so entities aren't double-escaped.
    public static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// MB → a human "N GB" (whole when even, one decimal otherwise).
    public static func gb(_ mb: Int) -> String {
        let g = Double(mb) / 1024.0
        return g == g.rounded() ? "\(Int(g)) GB" : String(format: "%.1f GB", g)
    }

    /// status → tag CSS class: running (green), stopped (muted), transitional (pulses), else warning.
    /// The single source of truth for this mapping — the panel sends it to the client as `cls`.
    public static func statusClass(_ s: String) -> String {
        if s == "running" { return "run" }
        if s == "stopped" { return "" }
        if s == "provisioning" || s == "starting" || s == "restarting" { return "prog" }
        return "warn"   // unhealthy / flapping / failed
    }
}
