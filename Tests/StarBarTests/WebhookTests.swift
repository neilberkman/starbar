import XCTest
@testable import StarBar

final class WebhookTests: XCTestCase {

  func testDecodeStarWebhook() throws {
    let data = try loadFixture(named: "star_webhook.json")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try decoder.decode(WebhookPayload.self, from: data)

    // Verify star event fields
    XCTAssertEqual(payload.action, "started")
    XCTAssertNotNil(payload.sender)
    XCTAssertEqual(payload.sender?.login, "neilberkman")
    XCTAssertEqual(payload.repository.fullName, "neilberkman/clippy")
    XCTAssertEqual(payload.repository.stargazersCount, 165)

    // Note: GitHub star webhooks don't include starred_at timestamp
    XCTAssertNil(payload.starredAt)
  }

  func testDecodePingWebhook() throws {
    let data = try loadFixture(named: "ping_webhook.json")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try decoder.decode(WebhookPayload.self, from: data)

    // Verify ping event fields
    XCTAssertNil(payload.action, "Ping webhooks should not have action field")
    XCTAssertNotNil(payload.sender, "Ping webhooks include sender (repo owner)")
    XCTAssertEqual(payload.repository.fullName, "neilberkman/clippy")
    XCTAssertNil(payload.starredAt)
  }

  func testAllFixturesDecodeSuccessfully() throws {
    let fixturesURL = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    let files = try FileManager.default.contentsOfDirectory(at: fixturesURL, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }

    XCTAssertGreaterThan(files.count, 0, "Should have at least one fixture")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for file in files {
      let data = try Data(contentsOf: file)
      XCTAssertNoThrow(
        try decoder.decode(WebhookPayload.self, from: data),
        "Failed to decode \(file.lastPathComponent)"
      )
    }
  }

  func testStarWebhookHasRequiredFields() throws {
    let data = try loadFixture(named: "star_webhook.json")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let payload = try decoder.decode(WebhookPayload.self, from: data)

    // Star events must have these fields for notifications to work
    guard let action = payload.action else {
      XCTFail("Star webhook must have action field")
      return
    }

    guard let sender = payload.sender else {
      XCTFail("Star webhook must have sender field")
      return
    }

    XCTAssertEqual(action, "started")
    XCTAssertFalse(sender.login.isEmpty)
    XCTAssertFalse(payload.repository.fullName.isEmpty)
    XCTAssertGreaterThan(payload.repository.stargazersCount, 0)
  }

  func testPingWebhookCanBeIdentified() throws {
    let starData = try loadFixture(named: "star_webhook.json")
    let pingData = try loadFixture(named: "ping_webhook.json")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let starPayload = try decoder.decode(WebhookPayload.self, from: starData)
    let pingPayload = try decoder.decode(WebhookPayload.self, from: pingData)

    // Test the identification logic from AppDelegate
    XCTAssertTrue(isPingWebhook(starPayload) == false, "Star should not be identified as ping")
    XCTAssertTrue(isPingWebhook(pingPayload) == true, "Ping should be identified as ping")
  }

  // MARK: - Helper Methods

  private func loadFixture(named: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: "Fixtures/\(named)", withExtension: nil) else {
      throw TestError.fixtureNotFound(named)
    }
    return try Data(contentsOf: url)
  }

  private func isPingWebhook(_ payload: WebhookPayload) -> Bool {
    return payload.action == nil || payload.sender == nil
  }

  enum TestError: Error {
    case fixtureNotFound(String)
  }
}
