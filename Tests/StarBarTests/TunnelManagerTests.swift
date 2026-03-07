import XCTest
@testable import StarBar

final class TunnelManagerTests: XCTestCase {
  func testParseTunnelURLFromCloudflareOutput() {
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

  func testParseTunnelURLFromNgrokJSONLogLine() {
    let output = #"{"addr":"http://localhost:63472","lvl":"info","msg":"started tunnel","name":"command_line","obj":"tunnels","t":"2026-03-07T03:51:06.333981-08:00","url":"https://1b9aa411aea5.ngrok.app"}"#

    let url = TunnelManager.parseURL(from: output)
    XCTAssertEqual(url, "https://1b9aa411aea5.ngrok.app")
  }

  func testParseTunnelURLFromLegacyNgrokFreeDomain() {
    let output = "url=https://abc123.ngrok-free.app"

    let url = TunnelManager.parseURL(from: output)
    XCTAssertEqual(url, "https://abc123.ngrok-free.app")
  }
}
