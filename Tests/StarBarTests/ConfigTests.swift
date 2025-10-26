import XCTest
@testable import StarBar

class ConfigTests: XCTestCase {
    func testLoadConfigFromDisk() {
        let testPath = "/tmp/starbar-test-config.json"
        let json = """
        {
            "github_token": "test_token_123",
            "state": {
                "last_full_scan": "2025-10-26T15:00:00Z",
                "scan_interval_days": 7,
                "tracked_repos": ["user/repo1"]
            }
        }
        """
        try! json.write(toFile: testPath, atomically: true, encoding: .utf8)

        let config = Config.load(from: testPath)

        XCTAssertEqual(config?.githubToken, "test_token_123")
        XCTAssertEqual(config?.state.trackedRepos.count, 1)
    }
}
