# StarBar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar app that delivers real-time GitHub star notifications using webhooks and polling.

**Architecture:** Swift AppKit app with local HTTP server for webhooks, cloudflared subprocess for tunnel, GitHub API client for polling, native notifications for alerts.

**Tech Stack:** Swift 5.9+, AppKit (NSStatusBar), URLSession, Process API, UserNotifications

---

## Task 1: Xcode Project Setup

**Files:**

- Create: `StarBar.xcodeproj`
- Create: `StarBar/Info.plist`
- Create: `StarBar/AppDelegate.swift`
- Create: `StarBar/main.swift`

**Step 1: Create Xcode project**

Open Terminal in `/Users/neil/xuku/starbar`:

```bash
mkdir -p StarBar
cd StarBar
```

Create `main.swift`:

```swift
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**Step 2: Create AppDelegate skeleton**

Create `AppDelegate.swift`:

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        print("StarBar started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("StarBar shutting down")
    }
}
```

**Step 3: Create Xcode project file**

Run in `/Users/neil/xuku/starbar`:

```bash
cat > StarBar.xcodeproj/project.pbxproj << 'EOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {
		MAINGROUP /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 1500;
			};
			buildConfigurationList = BUILDCONFIGLIST /* Build configuration list for PBXProject "StarBar" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = GROUP;
			productRefGroup = PRODUCTS;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				TARGET,
			);
		};
	};
	rootObject = MAINGROUP;
}
EOF
```

**Step 4: Create Info.plist**

Create `StarBar/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>com.starbar.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2025</string>
</dict>
</plist>
```

**Step 5: Build and test**

```bash
swift build
# OR use Xcode: open StarBar.xcodeproj
```

Expected: Build succeeds, app shows star icon in menu bar

**Step 6: Commit**

```bash
git add .
git commit -m "Initial Xcode project setup with menu bar icon"
```

---

## Task 2: Configuration Management

**Files:**

- Create: `StarBar/Config.swift`
- Create: `StarBar/Models/AppState.swift`
- Create: `StarBarTests/ConfigTests.swift`

**Step 1: Write test for config loading**

Create `StarBarTests/ConfigTests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

```bash
swift test
```

Expected: FAIL with "Config not defined"

**Step 3: Create models**

Create `StarBar/Models/AppState.swift`:

```swift
import Foundation

struct AppState: Codable {
    var lastFullScan: Date?
    var scanIntervalDays: Int
    var userWebhookId: Int?
    var trackedRepos: [String]
    var repos: [String: RepoState]

    enum CodingKeys: String, CodingKey {
        case lastFullScan = "last_full_scan"
        case scanIntervalDays = "scan_interval_days"
        case userWebhookId = "user_webhook_id"
        case trackedRepos = "tracked_repos"
        case repos
    }

    init() {
        scanIntervalDays = 7
        trackedRepos = []
        repos = [:]
    }
}

struct RepoState: Codable {
    var lastStarAt: Date?
    var starCount: Int

    enum CodingKeys: String, CodingKey {
        case lastStarAt = "last_star_at"
        case starCount = "star_count"
    }
}
```

**Step 4: Implement Config**

Create `StarBar/Config.swift`:

```swift
import Foundation

class Config: Codable {
    var githubToken: String
    var state: AppState

    enum CodingKeys: String, CodingKey {
        case githubToken = "github_token"
        case state
    }

    init(githubToken: String = "", state: AppState = AppState()) {
        self.githubToken = githubToken
        self.state = state
    }

    static func load(from path: String) -> Config? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(Config.self, from: data)
    }

    func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static var defaultPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let starbarDir = appSupport.appendingPathComponent("StarBar")
        try? FileManager.default.createDirectory(at: starbarDir, withIntermediateDirectories: true)
        return starbarDir.appendingPathComponent("config.json").path
    }
}
```

**Step 5: Run test to verify it passes**

```bash
swift test
```

Expected: PASS

**Step 6: Commit**

```bash
git add StarBar/Config.swift StarBar/Models/ StarBarTests/
git commit -m "Add configuration management with disk persistence"
```

---

## Task 3: Tunnel Manager (Cloudflared Subprocess)

**Files:**

- Create: `StarBar/TunnelManager.swift`
- Create: `StarBarTests/TunnelManagerTests.swift`

**Step 1: Write test for tunnel URL parsing**

Create `StarBarTests/TunnelManagerTests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

```bash
swift test
```

Expected: FAIL with "TunnelManager not defined"

**Step 3: Implement TunnelManager**

Create `StarBar/TunnelManager.swift`:

```swift
import Foundation

class TunnelManager {
    private var process: Process?
    private(set) var tunnelURL: String?
    private var outputPipe = Pipe()
    private var errorPipe = Pipe()

    static func parseURL(from output: String) -> String? {
        let pattern = "https://[a-zA-Z0-9-]+\\.trycloudflare\\.com"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range) else { return nil }

        return String(output[Range(match.range, in: output)!])
    }

    func start(port: Int = 3000, timeout: TimeInterval = 10) async throws -> String {
        // Check if cloudflared is installed
        let checkProcess = Process()
        checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        checkProcess.arguments = ["cloudflared"]

        try checkProcess.run()
        checkProcess.waitUntilExit()

        guard checkProcess.terminationStatus == 0 else {
            throw TunnelError.cloudflaredNotInstalled
        }

        // Start tunnel
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cloudflared")
        process?.arguments = ["tunnel", "--url", "http://localhost:\(port)"]

        process?.standardOutput = outputPipe
        process?.standardError = errorPipe

        try process?.run()

        // Parse URL from output with timeout
        let startTime = Date()
        var output = ""

        while Date().timeIntervalSince(startTime) < timeout {
            if let data = try? outputPipe.fileHandleForReading.availableData,
               !data.isEmpty {
                output += String(data: data, encoding: .utf8) ?? ""

                if let url = Self.parseURL(from: output) {
                    tunnelURL = url
                    return url
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        throw TunnelError.urlParseTimeout
    }

    func stop() {
        process?.terminate()
        process = nil
        tunnelURL = nil
    }

    enum TunnelError: Error {
        case cloudflaredNotInstalled
        case urlParseTimeout
    }
}
```

**Step 4: Run test to verify it passes**

```bash
swift test
```

Expected: PASS

**Step 5: Integration test (manual)**

Add to `AppDelegate.swift` in `applicationDidFinishLaunching`:

```swift
let tunnelManager = TunnelManager()
Task {
    do {
        let url = try await tunnelManager.start()
        print("Tunnel started at: \(url)")
    } catch {
        print("Tunnel error: \(error)")
    }
}
```

Run app, verify tunnel URL prints.

**Step 6: Commit**

```bash
git add StarBar/TunnelManager.swift StarBarTests/TunnelManagerTests.swift
git commit -m "Add tunnel manager for cloudflared subprocess"
```

---

## Task 4: GitHub API Client

**Files:**

- Create: `StarBar/GitHubAPI.swift`
- Create: `StarBar/Models/GitHubModels.swift`
- Create: `StarBarTests/GitHubAPITests.swift`

**Step 1: Write test for API client**

Create `StarBarTests/GitHubAPITests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

```bash
swift test
```

Expected: FAIL

**Step 3: Create GitHub models**

Create `StarBar/Models/GitHubModels.swift`:

```swift
import Foundation

struct GitHubRepo: Codable {
    let fullName: String
    let stargazersCount: Int

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case stargazersCount = "stargazers_count"
    }
}

struct Stargazer: Codable {
    let starredAt: Date
    let user: GitHubUser

    enum CodingKeys: String, CodingKey {
        case starredAt = "starred_at"
        case user
    }
}

struct GitHubUser: Codable {
    let login: String
}

struct WebhookPayload: Codable {
    let action: String
    let repository: Repository
    let sender: GitHubUser
    let starredAt: Date?

    struct Repository: Codable {
        let fullName: String
        let stargazersCount: Int

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case stargazersCount = "stargazers_count"
        }
    }

    enum CodingKeys: String, CodingKey {
        case action
        case repository
        case sender
        case starredAt = "starred_at"
    }
}

struct WebhookCreateRequest: Codable {
    let name = "web"
    let active = true
    let events = ["watch"]
    let config: WebhookConfig

    struct WebhookConfig: Codable {
        let url: String
        let contentType = "json"
        let secret: String

        enum CodingKeys: String, CodingKey {
            case url
            case contentType = "content_type"
            case secret
        }
    }
}

struct WebhookResponse: Codable {
    let id: Int
    let url: String
}
```

**Step 4: Implement GitHub API client**

Create `StarBar/GitHubAPI.swift`:

```swift
import Foundation

class GitHubAPI {
    private let token: String
    private let baseURL = "https://api.github.com"

    init(token: String) {
        self.token = token
    }

    func createWebhookRequest(username: String, webhookURL: String) -> URLRequest {
        let url = URL(string: "\(baseURL)/users/\(username)/hooks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        return request
    }

    func createWebhook(username: String, webhookURL: String) async throws -> Int {
        let secret = UUID().uuidString
        let payload = WebhookCreateRequest(
            config: WebhookCreateRequest.WebhookConfig(
                url: webhookURL,
                secret: secret
            )
        )

        var request = createWebhookRequest(username: username, webhookURL: webhookURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        let webhookResponse = try JSONDecoder().decode(WebhookResponse.self, from: data)
        return webhookResponse.id
    }

    func deleteWebhook(username: String, webhookId: Int) async throws {
        let url = URL(string: "\(baseURL)/users/\(username)/hooks/\(webhookId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw APIError.requestFailed
        }
    }

    func listWebhooks(username: String) async throws -> [WebhookResponse] {
        let url = URL(string: "\(baseURL)/users/\(username)/hooks")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([WebhookResponse].self, from: data)
    }

    func fetchRepos() async throws -> [GitHubRepo] {
        var allRepos: [GitHubRepo] = []
        var page = 1

        while true {
            let url = URL(string: "\(baseURL)/user/repos?per_page=100&page=\(page)")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)

            if repos.isEmpty { break }
            allRepos.append(contentsOf: repos)
            page += 1
        }

        return allRepos.filter { $0.stargazersCount > 0 }
    }

    func fetchStargazers(repo: String, since: Date?) async throws -> [Stargazer] {
        let url = URL(string: "\(baseURL)/repos/\(repo)/stargazers?per_page=100")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stargazers = try decoder.decode([Stargazer].self, from: data)

        if let since = since {
            return stargazers.filter { $0.starredAt > since }
        }

        return stargazers
    }

    enum APIError: Error {
        case requestFailed
    }
}
```

**Step 5: Run test to verify it passes**

```bash
swift test
```

Expected: PASS

**Step 6: Commit**

```bash
git add StarBar/GitHubAPI.swift StarBar/Models/GitHubModels.swift StarBarTests/GitHubAPITests.swift
git commit -m "Add GitHub API client for webhooks and stargazers"
```

---

## Task 5: Webhook HTTP Server

**Files:**

- Create: `StarBar/WebhookServer.swift`
- Create: `StarBarTests/WebhookServerTests.swift`

**Step 1: Write test for webhook parsing**

Create `StarBarTests/WebhookServerTests.swift`:

```swift
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
```

**Step 2: Run test**

```bash
swift test
```

Expected: PASS (models already defined)

**Step 3: Implement webhook server**

Create `StarBar/WebhookServer.swift`:

```swift
import Foundation
import Network

class WebhookServer {
    private var listener: NWListener?
    var onStarReceived: ((WebhookPayload) -> Void)?

    func start(port: UInt16 = 3000) throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let data = data, !data.isEmpty else { return }

            // Parse HTTP request
            let request = String(data: data, encoding: .utf8) ?? ""

            if request.contains("POST /webhook") {
                // Extract body from HTTP request
                if let bodyStart = request.range(of: "\r\n\r\n")?.upperBound {
                    let body = String(request[bodyStart...])
                    self?.handleWebhook(body: body)
                }

                // Send 200 OK
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else if request.contains("GET /health") {
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
    }

    private func handleWebhook(body: String) {
        guard let data = body.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let payload = try? decoder.decode(WebhookPayload.self, from: data) {
            onStarReceived?(payload)
        }
    }
}
```

**Step 4: Test manually**

Add to AppDelegate:

```swift
let server = WebhookServer()
server.onStarReceived = { payload in
    print("Star received: \(payload.repository.fullName) from \(payload.sender.login)")
}
try? server.start()
```

Test with curl:

```bash
curl -X POST http://localhost:3000/webhook -d '{"action":"created","repository":{"full_name":"test/repo","stargazers_count":1},"sender":{"login":"user"}}'
```

Expected: Print statement in console

**Step 5: Commit**

```bash
git add StarBar/WebhookServer.swift StarBarTests/WebhookServerTests.swift
git commit -m "Add webhook HTTP server for GitHub events"
```

---

## Task 6: Notification Manager

**Files:**

- Create: `StarBar/NotificationManager.swift`

**Step 1: Implement notification manager**

Create `StarBar/NotificationManager.swift`:

```swift
import Cocoa
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var badgeCount = 0
    weak var statusItem: NSStatusItem?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestPermission()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func showStarNotification(repo: String, user: String) {
        let content = UNMutableNotificationContent()
        content.title = "⭐ New Star"
        content.body = "\(repo) from @\(user)"
        content.sound = .default
        content.userInfo = ["repo": repo]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)

        incrementBadge()
    }

    func incrementBadge() {
        badgeCount += 1
        updateBadge()
    }

    func clearBadge() {
        badgeCount = 0
        updateBadge()
    }

    private func updateBadge() {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem?.button else { return }

            if self?.badgeCount ?? 0 > 0 {
                button.image = self?.createBadgedIcon(count: self?.badgeCount ?? 0)
            } else {
                button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
            }
        }
    }

    private func createBadgedIcon(count: Int) -> NSImage {
        let baseImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "StarBar")!
        let size = NSSize(width: 22, height: 22)

        let image = NSImage(size: size)
        image.lockFocus()

        // Draw star
        baseImage.draw(in: NSRect(origin: .zero, size: size))

        // Draw badge
        if count > 0 {
            let badgeSize: CGFloat = 12
            let badge = NSRect(x: size.width - badgeSize, y: 0, width: badgeSize, height: badgeSize)

            NSColor.red.setFill()
            let path = NSBezierPath(ovalIn: badge)
            path.fill()

            let text = count > 99 ? "99+" : "\(count)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor.white
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = NSRect(
                x: badge.midX - textSize.width / 2,
                y: badge.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
        }

        image.unlockFocus()
        return image
    }

    // Handle notification clicks
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let repo = response.notification.request.content.userInfo["repo"] as? String {
            let url = URL(string: "https://github.com/\(repo)")!
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
```

**Step 2: Test manually**

Add to AppDelegate:

```swift
let notificationManager = NotificationManager()
notificationManager.statusItem = statusItem
notificationManager.showStarNotification(repo: "user/test", user: "testuser")
```

Run app, verify notification appears and badge shows.

**Step 3: Commit**

```bash
git add StarBar/NotificationManager.swift
git commit -m "Add notification manager with badge support"
```

---

## Task 7: Network Monitor

**Files:**

- Create: `StarBar/NetworkMonitor.swift`

**Step 1: Implement network monitor**

Create `StarBar/NetworkMonitor.swift`:

```swift
import Foundation
import Network

class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    var onNetworkChange: (() -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.onNetworkChange?()
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
```

**Step 2: Commit**

```bash
git add StarBar/NetworkMonitor.swift
git commit -m "Add network change monitor"
```

---

## Task 8: Main App Orchestration

**Files:**

- Modify: `StarBar/AppDelegate.swift`

**Step 1: Integrate all components**

Replace `AppDelegate.swift`:

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var config: Config?
    var tunnelManager: TunnelManager?
    var webhookServer: WebhookServer?
    var gitHubAPI: GitHubAPI?
    var notificationManager: NotificationManager?
    var networkMonitor: NetworkMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        loadConfig()

        if config?.githubToken.isEmpty ?? true {
            showSetupWindow()
        } else {
            startServices()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
        }

        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()

        let totalStars = config?.state.repos.values.reduce(0) { $0 + $1.starCount } ?? 0
        menu.addItem(NSMenuItem(title: "Total Stars: \(totalStars)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Rescan Repos Now", action: #selector(rescanRepos), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Clear Badge", action: #selector(clearBadge), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func loadConfig() {
        config = Config.load(from: Config.defaultPath)
        if config == nil {
            config = Config()
        }
    }

    func saveConfig() {
        try? config?.save(to: Config.defaultPath)
    }

    func showSetupWindow() {
        let alert = NSAlert()
        alert.messageText = "Welcome to StarBar"
        alert.informativeText = "Enter your GitHub token to get started.\n\nCreate one at:\nhttps://github.com/settings/tokens/new?scopes=repo,admin:repo_hook"
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "ghp_xxxxxxxxxxxx"
        alert.accessoryView = input

        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            config?.githubToken = input.stringValue
            saveConfig()
            startServices()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    func startServices() {
        guard let token = config?.githubToken, !token.isEmpty else { return }

        gitHubAPI = GitHubAPI(token: token)
        notificationManager = NotificationManager()
        notificationManager?.statusItem = statusItem

        Task {
            await startTunnel()
            await performInitialScan()
            setupNetworkMonitoring()
        }
    }

    func startTunnel() async {
        tunnelManager = TunnelManager()
        webhookServer = WebhookServer()

        // Start webhook server
        try? webhookServer?.start()

        // Start tunnel
        do {
            let tunnelURL = try await tunnelManager?.start() ?? ""
            print("Tunnel started: \(tunnelURL)")

            // Clean old webhooks
            await cleanOldWebhooks()

            // Create new webhook
            await createWebhook(url: "\(tunnelURL)/webhook")

            // Setup webhook handler
            webhookServer?.onStarReceived = { [weak self] payload in
                self?.handleStarEvent(payload: payload)
            }
        } catch {
            print("Tunnel error: \(error)")
        }
    }

    func cleanOldWebhooks() async {
        // TODO: Implement webhook cleanup
    }

    func createWebhook(url: String) async {
        // TODO: Implement webhook creation
    }

    func performInitialScan() async {
        guard let api = gitHubAPI else { return }

        do {
            // Fetch repos
            let repos = try await api.fetchRepos()
            config?.state.trackedRepos = repos.map { $0.fullName }

            // Poll for new stars
            for repoName in config?.state.trackedRepos ?? [] {
                let lastStarAt = config?.state.repos[repoName]?.lastStarAt
                let newStars = try await api.fetchStargazers(repo: repoName, since: lastStarAt)

                for star in newStars {
                    notificationManager?.showStarNotification(
                        repo: repoName,
                        user: star.user.login
                    )
                }

                // Update state
                if let mostRecent = newStars.first {
                    if config?.state.repos[repoName] == nil {
                        config?.state.repos[repoName] = RepoState(starCount: 0)
                    }
                    config?.state.repos[repoName]?.lastStarAt = mostRecent.starredAt
                    config?.state.repos[repoName]?.starCount += newStars.count
                }
            }

            saveConfig()
            updateMenu()
        } catch {
            print("Scan error: \(error)")
        }
    }

    func setupNetworkMonitoring() {
        networkMonitor = NetworkMonitor()
        networkMonitor?.onNetworkChange = { [weak self] in
            Task {
                await self?.handleNetworkChange()
            }
        }
        networkMonitor?.start()
    }

    func handleNetworkChange() async {
        print("Network changed, restarting tunnel...")
        tunnelManager?.stop()
        await startTunnel()
    }

    func handleStarEvent(payload: WebhookPayload) {
        let repo = payload.repository.fullName

        // Add to tracked repos if new
        if !config?.state.trackedRepos.contains(repo) ?? false {
            config?.state.trackedRepos.append(repo)
        }

        // Update state
        if config?.state.repos[repo] == nil {
            config?.state.repos[repo] = RepoState(starCount: payload.repository.stargazersCount)
        }
        config?.state.repos[repo]?.lastStarAt = payload.starredAt ?? Date()
        config?.state.repos[repo]?.starCount = payload.repository.stargazersCount

        // Show notification
        notificationManager?.showStarNotification(repo: repo, user: payload.sender.login)

        saveConfig()
        updateMenu()
    }

    @objc func rescanRepos() {
        Task {
            await performInitialScan()
        }
    }

    @objc func clearBadge() {
        notificationManager?.clearBadge()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        webhookServer?.stop()
        tunnelManager?.stop()
        networkMonitor?.stop()
        saveConfig()
    }
}
```

**Step 2: Build and test**

```bash
swift build
# Run from Xcode
```

Expected: Full app flow works end-to-end

**Step 3: Commit**

```bash
git add StarBar/AppDelegate.swift
git commit -m "Integrate all components in main app orchestration"
```

---

## Task 9: README and Distribution

**Files:**

- Create: `README.md`
- Create: `.gitignore`

**Step 1: Create README**

Create `README.md`:

````markdown
# StarBar

Real-time GitHub star notifications in your Mac menu bar.

## Features

- Real-time notifications when your repos get starred
- Automatic catch-up on missed stars when offline
- Native macOS menu bar app
- Zero configuration (just paste GitHub token)
- Weekly auto-scan for new repos

## Installation

### Requirements

- macOS 13.0+
- Homebrew (for cloudflared)

### Steps

1. Install cloudflared:
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```
````

2. Download StarBar.app from [Releases](https://github.com/yourusername/starbar/releases)

3. Move to Applications:

   ```bash
   mv StarBar.app /Applications/
   ```

4. First launch (bypass Gatekeeper):
   - Right-click StarBar.app
   - Click "Open"
   - Click "Open" in the dialog

5. Create GitHub token:
   - Visit: https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook
   - Generate token
   - Paste in StarBar setup window

## Usage

- Click menu bar icon to see recent stars
- "Rescan Repos Now" to manually check for new repos
- "Clear Badge" to reset notification count

## Building from Source

```bash
git clone https://github.com/yourusername/starbar
cd starbar
open StarBar.xcodeproj
# Build in Xcode
```

## License

MIT

```

**Step 2: Create .gitignore**

Create `.gitignore`:
```

# Xcode

_.xcuserstate
xcuserdata/
DerivedData/
_.moved-aside
_.xccheckout
_.xcscmblueprint

# Swift

.build/
Packages/
_.swp
_~.nib

# macOS

.DS_Store

# Config (contains token)

config.json

````

**Step 3: Commit**

```bash
git add README.md .gitignore
git commit -m "Add README and gitignore"
````

---

## Summary

This plan creates StarBar in 9 tasks:

1. Xcode project setup with menu bar
2. Configuration management (JSON persistence)
3. Tunnel manager (cloudflared subprocess)
4. GitHub API client (webhooks, repos, stargazers)
5. Webhook HTTP server (local receiver)
6. Notification manager (native alerts + badge)
7. Network monitor (detect WiFi changes)
8. Main orchestration (integrate everything)
9. Documentation (README, distribution)

Each task is test-driven where appropriate, with frequent commits following DRY and YAGNI principles.
