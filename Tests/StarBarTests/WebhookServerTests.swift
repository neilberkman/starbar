import XCTest
@testable import StarBar

class WebhookServerTests: XCTestCase {
    func testParseWebhookPayload() {
        let json = """
        {
            "action": "created",
            "repository": {
                "full_name": "user/repo",
                "stargazers_count": 42
            },
            "sender": {
                "login": "testuser"
            },
            "starred_at": "2025-10-26T15:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try? decoder.decode(WebhookPayload.self, from: data)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.repository.fullName, "user/repo")
    }
}
