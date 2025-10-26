import XCTest
@testable import StarBar

class GitHubAPITests: XCTestCase {
    func testBuildWebhookRequest() {
        let api = GitHubAPI(token: "test_token")
        let request = api.createWebhookRequest(
            username: "testuser",
            webhookURL: "https://test.trycloudflare.com/webhook"
        )

        XCTAssertEqual(request.url?.path, "/users/testuser/hooks")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
