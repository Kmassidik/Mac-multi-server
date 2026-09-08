import XCTest
@testable import Panel

/// Unit tests for the panel's pure functions — no I/O, no network, no VMs.
/// These guard the small contracts the UI depends on: the status→CSS-class mapping
/// (now computed server-side and sent as `cls`), HTML escaping, the RAM formatter,
/// and the JSON DTOs the dashboard polls. Run with `swift test`.
final class PanelTests: XCTestCase {

    // MARK: status → CSS class (the one place this mapping lives)
    func testStatusClass() {
        XCTAssertEqual(Pages.statusClass("running"), "run")
        XCTAssertEqual(Pages.statusClass("stopped"), "")          // muted, no class
        // transitional states pulse ("prog")
        for s in ["provisioning", "starting", "restarting"] {
            XCTAssertEqual(Pages.statusClass(s), "prog", "\(s) should be prog")
        }
        // everything else is a warning (amber)
        for s in ["unhealthy", "flapping", "failed", "", "banana"] {
            XCTAssertEqual(Pages.statusClass(s), "warn", "\(s) should be warn")
        }
    }

    // MARK: MB → "N GB"
    func testGB() {
        XCTAssertEqual(Pages.gb(1024), "1 GB")     // whole → no decimal
        XCTAssertEqual(Pages.gb(4096), "4 GB")
        XCTAssertEqual(Pages.gb(1536), "1.5 GB")   // fractional → one decimal
        XCTAssertEqual(Pages.gb(512), "0.5 GB")
        XCTAssertEqual(Pages.gb(0), "0 GB")
    }

    // MARK: HTML escaping (XSS guard for every dynamic value in a page)
    func testEsc() {
        XCTAssertEqual(Pages.esc("plain text"), "plain text")
        XCTAssertEqual(Pages.esc("<script>"), "&lt;script&gt;")
        XCTAssertEqual(Pages.esc("a & b"), "a &amp; b")
        XCTAssertEqual(Pages.esc("say \"hi\""), "say &quot;hi&quot;")
        // & must be escaped first so entities aren't double-escaped
        XCTAssertEqual(Pages.esc("<&>"), "&lt;&amp;&gt;")
    }

    // MARK: JSON DTOs the dashboard polls
    func testStatusDTOEncodes() throws {
        let data = try JSONEncoder().encode(StatusDTO(status: "running", cls: "run"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(obj["status"], "running")
        XCTAssertEqual(obj["cls"], "run")
        XCTAssertEqual(obj.count, 2)
    }

    func testVPSRowDTOEncodes() throws {
        let data = try JSONEncoder().encode(VPSRowDTO(name: "vps-1", status: "stopped", cls: ""))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(obj["name"], "vps-1")
        XCTAssertEqual(obj["status"], "stopped")
        XCTAssertEqual(obj["cls"], "")            // stopped → empty class, still present
        XCTAssertEqual(obj.count, 3)
    }

    /// The class in a row must always match statusClass(status) — i.e. the server and the
    /// (removed) client mapping can never diverge, because there's only one source now.
    func testRowClassMatchesStatusClass() {
        for s in ["running", "stopped", "provisioning", "unhealthy", "failed"] {
            let row = VPSRowDTO(name: "vps-x", status: s, cls: Pages.statusClass(s))
            XCTAssertEqual(row.cls, Pages.statusClass(s))
        }
    }
}
