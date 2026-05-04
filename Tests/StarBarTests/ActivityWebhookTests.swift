import XCTest
@testable import StarBar

final class ActivityWebhookTests: XCTestCase {

  private func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }

  func testDecodeIssuePayload() throws {
    let json = """
    {
      "action": "opened",
      "issue": {
        "number": 42,
        "title": "Bug: thing broken",
        "html_url": "https://github.com/neilberkman/starbar/issues/42",
        "user": { "login": "external_user" },
        "created_at": "2026-04-01T12:00:00Z"
      },
      "repository": {
        "full_name": "neilberkman/starbar",
        "stargazers_count": 5
      },
      "sender": { "login": "external_user" }
    }
    """.data(using: .utf8)!

    let payload = try decoder().decode(IssuePayload.self, from: json)
    XCTAssertEqual(payload.action, "opened")
    XCTAssertEqual(payload.issue.number, 42)
    XCTAssertEqual(payload.issue.title, "Bug: thing broken")
    XCTAssertFalse(payload.issue.isPullRequest)
    XCTAssertEqual(payload.repository.fullName, "neilberkman/starbar")
    XCTAssertEqual(payload.sender.login, "external_user")
  }

  func testDecodePullRequestPayload() throws {
    let json = """
    {
      "action": "opened",
      "pull_request": {
        "number": 7,
        "title": "Add feature X",
        "html_url": "https://github.com/neilberkman/starbar/pull/7",
        "user": { "login": "contributor" },
        "created_at": "2026-04-01T12:00:00Z"
      },
      "repository": {
        "full_name": "neilberkman/starbar",
        "stargazers_count": 5
      },
      "sender": { "login": "contributor" }
    }
    """.data(using: .utf8)!

    let payload = try decoder().decode(PullRequestPayload.self, from: json)
    XCTAssertEqual(payload.action, "opened")
    XCTAssertEqual(payload.pullRequest.number, 7)
    XCTAssertEqual(payload.pullRequest.htmlUrl, "https://github.com/neilberkman/starbar/pull/7")
    XCTAssertEqual(payload.sender.login, "contributor")
  }

  func testIssueDistinguishesPullRequestFromRESTAPI() throws {
    // The /repos/{r}/issues REST endpoint returns PRs alongside issues; the
    // distinguishing field is `pull_request`. Verify Issue.isPullRequest works.
    let issueJson = """
    {
      "number": 1,
      "title": "real issue",
      "html_url": "https://github.com/x/y/issues/1",
      "user": { "login": "a" },
      "created_at": "2026-04-01T12:00:00Z"
    }
    """.data(using: .utf8)!

    let prJson = """
    {
      "number": 2,
      "title": "actually a PR",
      "html_url": "https://github.com/x/y/issues/2",
      "user": { "login": "a" },
      "created_at": "2026-04-01T12:00:00Z",
      "pull_request": { "html_url": "https://github.com/x/y/pull/2" }
    }
    """.data(using: .utf8)!

    let issue = try decoder().decode(Issue.self, from: issueJson)
    let pr = try decoder().decode(Issue.self, from: prJson)

    XCTAssertFalse(issue.isPullRequest)
    XCTAssertTrue(pr.isPullRequest)
    XCTAssertEqual(pr.pullRequest?.htmlUrl, "https://github.com/x/y/pull/2")
  }

  func testWebhookCreateRequestSubscribesToAllEvents() throws {
    let req = WebhookCreateRequest(
      config: .init(url: "https://example.com/webhook", secret: "s")
    )
    let data = try JSONEncoder().encode(req)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let events = json["events"] as! [String]
    XCTAssertEqual(Set(events), Set(["watch", "issues", "pull_request"]))
  }

  func testWebhookEventsSubscribedSetMatchesArray() {
    XCTAssertEqual(WebhookEvents.subscribedSet, Set(["watch", "issues", "pull_request"]))
  }

  func testWebhookEnvelopeExtractsRepoName() throws {
    let json = """
    {
      "action": "anything",
      "extra_unknown_field": 123,
      "repository": {
        "full_name": "owner/repo",
        "stargazers_count": 99
      }
    }
    """.data(using: .utf8)!

    let envelope = try decoder().decode(WebhookEnvelope.self, from: json)
    XCTAssertEqual(envelope.repository.fullName, "owner/repo")
  }

  func testWebhookResponseDecodesEventsField() throws {
    let json = """
    {
      "id": 123,
      "url": "https://api.github.com/repos/x/y/hooks/123",
      "config": { "url": "https://example.com/webhook" },
      "events": ["watch"]
    }
    """.data(using: .utf8)!

    let resp = try decoder().decode(WebhookResponse.self, from: json)
    XCTAssertEqual(resp.events, ["watch"])
  }

  func testWebhookResponseToleratesMissingEventsField() throws {
    let json = """
    {
      "id": 1,
      "url": "https://api.github.com/x",
      "config": { "url": "https://example.com/webhook" }
    }
    """.data(using: .utf8)!

    let resp = try decoder().decode(WebhookResponse.self, from: json)
    XCTAssertNil(resp.events)
  }
}
