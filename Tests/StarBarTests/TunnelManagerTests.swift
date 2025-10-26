import XCTest
@testable import StarBar

class TunnelManagerTests: XCTestCase {
    func testParseTunnelURLFromOutput() {
        let output = """
        2025-10-26T15:30:00Z INF Starting tunnel
        2025-10-26T15:30:01Z INF +--------------------------------------------------------------------------------------------+
        2025-10-26T15:30:01Z INF |  Your quick tunnel has been created! Visit it at:                                          |
        2025-10-26T15:30:01Z INF |  https://random-words-1234.trycloudflare.com                                              |
        2025-10-26T15:30:01Z INF +--------------------------------------------------------------------------------------------+
        """

        let url = TunnelManager.parseURL(from: output)
        XCTAssertEqual(url, "https://random-words-1234.trycloudflare.com")
    }
}
