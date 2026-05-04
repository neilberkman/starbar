import XCTest
@testable import StarBar

class ConfigTests: XCTestCase {
    private let testPath = "/tmp/starbar-test-config.json"
    private let testService = "com.xuku.starbar.test"
    private var originalService = Keychain.defaultService

    override func setUp() {
        super.setUp()
        originalService = Keychain.defaultService
        Keychain.defaultService = testService
        Keychain.deleteToken()
        try? FileManager.default.removeItem(atPath: testPath)
    }

    override func tearDown() {
        Keychain.deleteToken()
        try? FileManager.default.removeItem(atPath: testPath)
        Keychain.defaultService = originalService
        super.tearDown()
    }

    func testLoadConfigFromDisk() {
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

    func testMigratesLegacyTokenToKeychainAndScrubsJSON() {
        let json = """
        {
            "github_token": "legacy_secret_xyz",
            "state": {
                "scan_interval_days": 7,
                "tracked_repos": []
            }
        }
        """
        try! json.write(toFile: testPath, atomically: true, encoding: .utf8)

        XCTAssertNil(Keychain.getToken())

        let config = Config.load(from: testPath)
        XCTAssertEqual(config?.githubToken, "legacy_secret_xyz")
        XCTAssertEqual(Keychain.getToken(), "legacy_secret_xyz")

        let scrubbed = try! String(contentsOfFile: testPath, encoding: .utf8)
        XCTAssertFalse(scrubbed.contains("legacy_secret_xyz"))
        XCTAssertFalse(scrubbed.contains("github_token"))
    }

    func testLoadsTokenFromKeychainWhenJSONLacksToken() {
        try! Keychain.setToken("keychain_token_abc")

        let json = """
        {
            "state": {
                "scan_interval_days": 7,
                "tracked_repos": ["user/repo1"]
            }
        }
        """
        try! json.write(toFile: testPath, atomically: true, encoding: .utf8)

        let config = Config.load(from: testPath)
        XCTAssertEqual(config?.githubToken, "keychain_token_abc")
    }

    func testSaveDoesNotWriteTokenToJSON() {
        let config = Config(githubToken: "secret_value", state: AppState())
        try! config.save(to: testPath)

        let written = try! String(contentsOfFile: testPath, encoding: .utf8)
        XCTAssertFalse(written.contains("secret_value"))
        XCTAssertFalse(written.contains("github_token"))
        XCTAssertEqual(Keychain.getToken(), "secret_value")
    }
}
