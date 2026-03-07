import XCTest
@testable import StarBar

final class GitHubAPITests: XCTestCase {
  func testBuildRepoWebhookRequest() throws {
    let api = GitHubAPI(token: "test_token")
    let request = try api.createRepoWebhookRequest(
      repo: "testuser/testrepo",
      webhookURL: "https://test.ngrok.app/webhook",
      secret: "secret-value"
    )

    XCTAssertEqual(request.url?.path, "/repos/testuser/testrepo/hooks")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test_token")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github.v3+json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let body = try XCTUnwrap(request.httpBody)
    let payload = try JSONDecoder().decode(WebhookCreateRequest.self, from: body)
    XCTAssertEqual(payload.config.url, "https://test.ngrok.app/webhook")
    XCTAssertEqual(payload.config.secret, "secret-value")
    XCTAssertEqual(payload.events, ["watch"])
  }
}
