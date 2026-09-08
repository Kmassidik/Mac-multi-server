// pcheck — dependency-free unit checks for the panel's pure functions.
// No XCTest (the host is Command-Line-Tools only), so this is a plain executable:
// run `swift run pcheck` — it prints each check and exits non-zero if any failed.

import Foundation
import PanelCore

var passed = 0, failed = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { passed += 1; print("  ✓ \(name)") }
    else { failed += 1; print("  ✗ \(name): got \"\(got)\", want \"\(want)\"") }
}

print("PanelCore checks\n")

// status → CSS class (the single source of truth, sent to the client as `cls`)
check("statusClass running",      PanelCore.statusClass("running"),      "run")
check("statusClass stopped",      PanelCore.statusClass("stopped"),      "")
check("statusClass provisioning", PanelCore.statusClass("provisioning"), "prog")
check("statusClass starting",     PanelCore.statusClass("starting"),     "prog")
check("statusClass restarting",   PanelCore.statusClass("restarting"),   "prog")
check("statusClass unhealthy",    PanelCore.statusClass("unhealthy"),    "warn")
check("statusClass flapping",     PanelCore.statusClass("flapping"),     "warn")
check("statusClass failed",       PanelCore.statusClass("failed"),       "warn")
check("statusClass unknown",      PanelCore.statusClass("banana"),       "warn")

// MB → "N GB"
check("gb 1024",  PanelCore.gb(1024),  "1 GB")
check("gb 4096",  PanelCore.gb(4096),  "4 GB")
check("gb 1536",  PanelCore.gb(1536),  "1.5 GB")
check("gb 512",   PanelCore.gb(512),   "0.5 GB")
check("gb 0",     PanelCore.gb(0),     "0 GB")

// HTML escaping (XSS guard) — & first so entities aren't double-escaped
check("esc plain",  PanelCore.esc("plain text"),  "plain text")
check("esc script", PanelCore.esc("<script>"),    "&lt;script&gt;")
check("esc amp",    PanelCore.esc("a & b"),        "a &amp; b")
check("esc quote",  PanelCore.esc("say \"hi\""),  "say &quot;hi&quot;")
check("esc order",  PanelCore.esc("<&>"),          "&lt;&amp;&gt;")

print("\n\(passed) passed · \(failed) failed")
exit(failed == 0 ? 0 : 1)
