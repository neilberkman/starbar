import Cocoa
import ServiceManagement
import os.log

extension String {
  func appendingToFile(at path: String) throws {
    let url = URL(fileURLWithPath: path)
    if let data = self.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: path) {
        let fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      } else {
        try data.write(to: url)
      }
    }
  }
}

struct StarEvent {
  let repo: String
  let user: String
  let timestamp: Date
  var isRead: Bool
  let starNumber: Int?  // Which # star this was (e.g., star #157)
}

// Custom NSApplication to handle paste in menu bar apps
public class StarBarApplication: NSApplication {
  override public func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
    if action == #selector(NSText.paste(_:)) {
      if let firstResponder = keyWindow?.firstResponder as? NSText {
        firstResponder.paste(sender)
        return true
      }
    }
    return super.sendAction(action, to: target, from: sender)
  }
}

public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var statusItem: NSStatusItem?
  var config: Config?
  var tunnelManager: TunnelManager?
  var webhookServer: WebhookServer?
  var gitHubAPI: GitHubAPI?
  var notificationManager: NotificationManager?
  var networkMonitor: NetworkMonitor?
  var recentStars: [StarEvent] = []
  var setupTokenInput: NSTextField?
  var setupWindow: NSWindow?
  private var isScanning = false

  public override init() {
    super.init()
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenuBar()
    loadConfig()

    NSLog("📱 App launched, config loaded")
    NSLog("📱 Token exists: \(!(config?.githubToken.isEmpty ?? true))")

    // Check if cloudflared is installed
    if !isCloudflaredInstalled() {
      NSLog("⚠️ cloudflared not installed")
      showCloudflaredError()
      return
    }

    if config?.githubToken.isEmpty ?? true {
      NSLog("📱 No token, showing setup window")
      showSetupWindow()
    } else {
      NSLog("📱 Token found, starting services")
      startServices()
    }
  }

  func isCloudflaredInstalled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["cloudflared"]
    process.standardOutput = Pipe()
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
  }

  func showCloudflaredError() {
    let alert = NSAlert()
    alert.messageText = "Cloudflared Not Found"
    alert.informativeText = "StarBar requires cloudflared to create tunnels.\n\nInstall with: brew install cloudflared"
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    NSApplication.shared.terminate(nil)
  }

  func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem?.button {
      button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
      button.wantsLayer = true  // Enable layer for animations
    }

    updateMenu()
  }

  func setScanning(_ scanning: Bool) {
    isScanning = scanning
    guard let button = statusItem?.button else { return }
    if scanning {
      button.image = NSImage(systemSymbolName: "star.leadinghalf.filled", accessibilityDescription: "StarBar Scanning")
      startPulseAnimation()
    } else {
      stopPulseAnimation()
      // Restore based on badge count
      if let manager = notificationManager, manager.badgeCount > 0 {
        button.image = manager.createBadgedIcon(count: manager.badgeCount)
      } else {
        button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
      }
    }
    updateMenu()
  }

  func startPulseAnimation() {
    guard let button = statusItem?.button else { return }
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1.0
    animation.toValue = 0.3
    animation.duration = 0.8
    animation.autoreverses = true
    animation.repeatCount = .infinity
    button.layer?.add(animation, forKey: "pulse")
  }

  func stopPulseAnimation() {
    guard let button = statusItem?.button else { return }
    button.layer?.removeAnimation(forKey: "pulse")
    button.alphaValue = 1.0
  }

  public func menuNeedsUpdate(_ menu: NSMenu) {
    NSLog("🔍 menuNeedsUpdate called - updating timestamps")
    // Find the "Recent Stars" submenu and update timestamps
    for item in menu.items {
      if item.title == "Recent Stars", let submenu = item.submenu {
        let last10 = Array(recentStars.prefix(10))
        for (index, event) in last10.enumerated() where index < submenu.items.count {
          let timeAgo = timeAgoString(from: event.timestamp)
          let prefix = event.isRead ? "" : "• "
          let starNum = event.starNumber.map { " - Star #\($0)" } ?? ""
          let title = "\(prefix)⭐ \(event.repo) from @\(event.user)\(starNum) (\(timeAgo))"
          submenu.items[index].title = title
        }
        break
      }
    }
  }

  func updateMenu() {
    NSLog("🔍 updateMenu called, recentStars.count = \(recentStars.count)")
    let menu = NSMenu()
    menu.delegate = self

    let totalStars = config?.state.repos.values.reduce(0) { $0 + $1.starCount } ?? 0
    menu.addItem(NSMenuItem(title: "Total Stars: \(totalStars)", action: nil, keyEquivalent: ""))

    // Webhook status
    let webhookStatus = getWebhookStatus()
    menu.addItem(NSMenuItem(title: webhookStatus, action: nil, keyEquivalent: ""))

    menu.addItem(NSMenuItem.separator())

    // Recent Stars submenu
    if !recentStars.isEmpty {
      NSLog("🔍 Adding Recent Stars submenu with \(recentStars.count) stars")
      let recentItem = NSMenuItem(title: "Recent Stars", action: nil, keyEquivalent: "")
      let recentMenu = NSMenu()

      let last10 = Array(recentStars.prefix(10))
      for (index, event) in last10.enumerated() {
        let timeAgo = timeAgoString(from: event.timestamp)
        let prefix = event.isRead ? "" : "• "
        let starNum = event.starNumber.map { " - Star #\($0)" } ?? ""
        let title = "\(prefix)⭐ \(event.repo) from @\(event.user)\(starNum) (\(timeAgo))"
        let item = NSMenuItem(title: title, action: #selector(openStar(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        recentMenu.addItem(item)
      }

      recentItem.submenu = recentMenu
      menu.addItem(recentItem)
      menu.addItem(NSMenuItem.separator())
    }

    let rescanTitle = isScanning ? "Scanning..." : "Rescan Repos Now"
    let rescanItem = NSMenuItem(title: rescanTitle, action: #selector(rescanRepos), keyEquivalent: "r")
    rescanItem.target = self
    rescanItem.isEnabled = !isScanning
    menu.addItem(rescanItem)

    let clearItem = NSMenuItem(title: "Clear Badge", action: #selector(clearBadge), keyEquivalent: "")
    clearItem.target = self
    menu.addItem(clearItem)

    menu.addItem(NSMenuItem.separator())

    let launchItem = NSMenuItem(title: "Launch at Startup", action: #selector(toggleLaunchAtStartup), keyEquivalent: "")
    launchItem.target = self
    launchItem.state = isLaunchAtStartupEnabled() ? .on : .off
    menu.addItem(launchItem)

    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    statusItem?.menu = menu
  }

  func timeAgoString(from date: Date) -> String {
    let seconds = Date().timeIntervalSince(date)
    let minutes = Int(seconds / 60)
    let hours = Int(seconds / 3600)
    let days = Int(seconds / 86400)

    if days > 0 { return "\(days)d ago" }
    if hours > 0 { return "\(hours)h ago" }
    if minutes > 0 { return "\(minutes)m ago" }
    return "just now"
  }

  func getWebhookStatus() -> String {
    // Check tunnel status
    let tunnelStatus: String
    if let url = tunnelManager?.tunnelURL, !url.isEmpty {
      tunnelStatus = "✓ Tunnel Active"
    } else {
      tunnelStatus = "✗ Tunnel Offline"
    }

    // Get count of tracked repos
    let totalRepos = config?.state.trackedRepos.count ?? 0

    return "\(tunnelStatus) • Tracking: \(totalRepos) repos"
  }

  @objc func openStar(_ sender: NSMenuItem) {
    let index = sender.tag
    guard index < recentStars.count else { return }

    var event = recentStars[index]
    if !event.isRead {
      event.isRead = true
      recentStars[index] = event
      notificationManager?.decrementBadge()
      updateMenu()
    }

    let url = URL(string: "https://github.com/\(event.repo)/stargazers")!
    NSWorkspace.shared.open(url)
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
    // Activate app first so window can receive focus
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Create Edit menu for paste to work
    let mainMenu = NSMenu()
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)
    NSApp.mainMenu = mainMenu

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Welcome to StarBar"
    window.center()
    window.level = .floating

    let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))

    let textView = NSTextView(frame: NSRect(x: 20, y: 100, width: 460, height: 80))
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainer?.lineFragmentPadding = 0

    let text = "Paste your GitHub token below.\n\nCreate one at:\nhttps://github.com/settings/tokens/new?scopes=repo,admin:repo_hook"
    let attributedString = NSMutableAttributedString(string: text)

    // Set default text color to adapt to light/dark mode
    attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: text.count))

    // Make URL clickable
    if let urlRange = text.range(of: "https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook") {
      let nsRange = NSRange(urlRange, in: text)
      attributedString.addAttribute(.link, value: "https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook", range: nsRange)
      attributedString.addAttribute(.foregroundColor, value: NSColor.linkColor, range: nsRange)
    }

    textView.textStorage?.setAttributedString(attributedString)
    contentView.addSubview(textView)

    let input = NSTextField(frame: NSRect(x: 20, y: 60, width: 460, height: 24))
    input.placeholderString = "Paste token here (Cmd+V)"
    contentView.addSubview(input)
    setupTokenInput = input

    let startButton = NSButton(frame: NSRect(x: 400, y: 20, width: 80, height: 30))
    startButton.title = "Start"
    startButton.bezelStyle = .rounded
    startButton.keyEquivalent = "\r"
    startButton.target = self
    startButton.action = #selector(handleSetupStart(_:))
    contentView.addSubview(startButton)

    let quitButton = NSButton(frame: NSRect(x: 310, y: 20, width: 80, height: 30))
    quitButton.title = "Quit"
    quitButton.bezelStyle = .rounded
    quitButton.target = self
    quitButton.action = #selector(handleSetupQuit)
    contentView.addSubview(quitButton)

    window.contentView = contentView
    setupWindow = window
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(input)
  }

  @objc func handleSetupStart(_ sender: NSButton) {
    guard let input = setupTokenInput else { return }
    let token = input.stringValue

    config?.githubToken = token
    saveConfig()

    // Hide window and start services
    setupWindow?.orderOut(nil)

    // Start services in background
    Task {
      await startServicesAsync()

      // After services start, close window and switch to accessory mode
      DispatchQueue.main.async {
        self.setupWindow?.close()
        self.setupWindow = nil
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }

  func startServicesAsync() async {
    NSLog("→ startServicesAsync: CALLED")
    guard let token = config?.githubToken, !token.isEmpty else {
      NSLog("⚠️ startServicesAsync: No token found in config")
      return
    }

    NSLog("✓ startServicesAsync: Starting with token: \(token.prefix(7))...")
    gitHubAPI = GitHubAPI(token: token)

    // Create NotificationManager FIRST so it's ready for webhooks
    // TEMP DISABLED: Works in app bundle but crashes when run directly
    // TODO: Run via proper app bundle to enable notifications
    NSLog("⚠️ NotificationManager disabled (run via app bundle to enable)")
    // DispatchQueue.main.async {
    //   self.notificationManager = NotificationManager()
    //   self.notificationManager?.statusItem = self.statusItem
    //   NSLog("✓ NotificationManager created")
    // }

    // Start tunnel in background - don't block scan
    Task {
      NSLog("→ startServicesAsync: Starting tunnel in background...")
      await startTunnel()
      NSLog("→ startServicesAsync: Setting up webhooks...")
      await setupWebhooks()
    }

    // Do scan immediately without waiting for tunnel
    NSLog("→ startServicesAsync: Performing initial scan...")
    await performInitialScan()
    NSLog("→ startServicesAsync: Setting up network monitoring...")
    setupNetworkMonitoring()

    NSLog("✓ startServicesAsync: All services started successfully")
  }

  @objc func handleSetupQuit() {
    NSApplication.shared.terminate(nil)
  }

  func startServices() {
    Task {
      await startServicesAsync()
    }
  }

  func startTunnel() async {
    print("→ startTunnel: Creating tunnel manager")
    tunnelManager = TunnelManager()
    webhookServer = WebhookServer()

    // Setup tunnel URL change handler
    tunnelManager?.onTunnelURLChanged = { [weak self] newURL in
      NSLog("🔄 Tunnel URL changed to: \(newURL)")
      Task {
        await self?.setupWebhooks()
      }
    }

    // Setup tunnel death handler
    tunnelManager?.onTunnelDied = { [weak self] in
      NSLog("💀 Tunnel died, restarting...")
      Task {
        await self?.handleNetworkChange()
      }
    }

    // Setup webhook handler BEFORE starting server
    // This way it works even if tunnel fails
    webhookServer?.onStarReceived = { [weak self] payload in
      self?.handleStarEvent(payload: payload)
    }

    // Setup webhook secret lookup for signature validation
    webhookServer?.getWebhookSecret = { [weak self] repoName in
      return self?.config?.state.repos[repoName]?.webhookSecret
    }

    // Start webhook server
    print("→ startTunnel: Starting webhook server")
    do {
      try webhookServer?.start()
      NSLog("✓ Webhook server started successfully")
    } catch {
      NSLog("❌ Webhook server failed to start: \(error)")
    }

    // Start tunnel
    print("→ startTunnel: Starting cloudflared tunnel")
    do {
      let tunnelURL = try await tunnelManager?.start() ?? ""
      print("✓ Tunnel started: \(tunnelURL)")
      print("✓ tunnelManager.tunnelURL = \(tunnelManager?.tunnelURL ?? "nil")")
    } catch {
      print("❌ Tunnel error: \(error)")
    }
  }

  func setupWebhooks() async {
    guard let tunnelURL = tunnelManager?.tunnelURL else {
      print("❌ setupWebhooks: No tunnel URL available!")
      print("❌ tunnelManager exists: \(tunnelManager != nil)")
      print("❌ tunnelManager.tunnelURL: \(tunnelManager?.tunnelURL ?? "nil")")
      return
    }

    print("✓ setupWebhooks: Using tunnel URL: \(tunnelURL)")

    // Clean old webhooks
    await cleanOldWebhooks()

    // Create new webhooks
    await createWebhook(url: "\(tunnelURL)/webhook")
  }

  func cleanOldWebhooks() async {
    guard let api = gitHubAPI else { return }

    // Clean webhooks for all tracked repos
    for repoName in config?.state.trackedRepos ?? [] {
      do {
        let webhooks = try await api.listRepoWebhooks(repo: repoName)

        // Delete webhooks pointing to trycloudflare.com (our old tunnels)
        for webhook in webhooks {
          if webhook.url.contains("trycloudflare.com") {
            try await api.deleteRepoWebhook(repo: repoName, webhookId: webhook.id)
            NSLog("Deleted old webhook from \(repoName): \(webhook.id)")
          }
        }
      } catch {
        NSLog("Error cleaning webhooks for \(repoName): \(error)")
      }
    }
  }

  func shouldCreateWebhook(for repoName: String) -> Bool {
    guard let repoState = config?.state.repos[repoName] else { return false }

    // Only create webhooks for "active" repos:
    // 1. Repos with significant stars (>10)
    if repoState.starCount > 10 { return true }

    // 2. Repos with recent star activity (starred in last 6 months)
    if let lastStar = repoState.lastStarAt {
      let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
      if lastStar > sixMonthsAgo { return true }
    }

    // 3. Very new repos (created in last 3 months) - use first star as proxy for creation
    if let lastStar = repoState.lastStarAt {
      let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
      if lastStar > threeMonthsAgo { return true }
    }

    return false
  }

  func createWebhook(url: String) async {
    guard let api = gitHubAPI else { return }

    // Filter to only active repos
    let activeRepos = (config?.state.trackedRepos ?? []).filter { shouldCreateWebhook(for: $0) }
    NSLog("Creating webhooks for \(activeRepos.count)/\(config?.state.trackedRepos.count ?? 0) active repos")

    // Create webhook for each active repo
    var successCount = 0
    for repoName in activeRepos {
      do {
        // First, delete ONLY our old tunnel webhooks (cloudflare + ngrok) to avoid conflicts
        let existingHooks = try await api.listRepoWebhooks(repo: repoName)
        let ourOldHooks = existingHooks.filter {
          $0.config.url.contains("trycloudflare.com") || $0.config.url.contains("ngrok.app")
        }
        if !ourOldHooks.isEmpty {
          NSLog("Found \(ourOldHooks.count) old StarBar webhooks for \(repoName), deleting...")
          for hook in ourOldHooks {
            do {
              try await api.deleteRepoWebhook(repo: repoName, webhookId: hook.id)
              NSLog("✓ Deleted old StarBar webhook \(hook.id) (\(hook.config.url))")
            } catch {
              NSLog("⚠️ Failed to delete webhook \(hook.id): \(error)")
            }
          }
        }

        // Now create the new webhook
        let (webhookId, secret) = try await api.createRepoWebhook(repo: repoName, webhookURL: url)

        // Store the webhook secret for validation
        if config?.state.repos[repoName] == nil {
          config?.state.repos[repoName] = RepoState(lastStarAt: nil, starCount: 0, webhookSecret: secret)
        } else {
          config?.state.repos[repoName]?.webhookSecret = secret
        }
        saveConfig()

        successCount += 1
        NSLog("✓ Created webhook for \(repoName): \(webhookId)")
      } catch {
        NSLog("Error creating webhook for \(repoName): \(error)")
      }
    }

    NSLog("Created \(successCount)/\(activeRepos.count) webhooks for active repos")
  }

  func performInitialScan() async {
    NSLog("🔍 performInitialScan: START")
    guard let api = gitHubAPI else {
      NSLog("❌ performInitialScan: No GitHub API instance!")
      return
    }

    NSLog("🔍 performInitialScan: Setting scanning state...")
    DispatchQueue.main.async {
      self.setScanning(true)
    }

    // Clear existing stars to avoid duplicates on rescan
    recentStars.removeAll()

    do {
      // Fetch repos
      NSLog("🔍 performInitialScan: Fetching repos from GitHub API...")
      let repos = try await api.fetchRepos()
      NSLog("🔍 performInitialScan: Fetched \(repos.count) repos with stars")
      config?.state.trackedRepos = repos.map { $0.fullName }
      NSLog("🔍 performInitialScan: Updated tracked_repos, saving config...")
      saveConfig()
      NSLog("🔍 performInitialScan: Config saved with \(config?.state.trackedRepos.count ?? 0) repos")

      // Create repo name to star count map
      let repoStarCounts = Dictionary(uniqueKeysWithValues: repos.map { ($0.fullName, $0.stargazersCount) })

      // Poll for new stars
      for repoName in config?.state.trackedRepos ?? [] {
        let lastStarAt = config?.state.repos[repoName]?.lastStarAt
        let isFirstScan = lastStarAt == nil
        let actualStarCount = repoStarCounts[repoName] ?? 0
        NSLog("🔍 Fetching stargazers for \(repoName), totalStars=\(actualStarCount), isFirstScan=\(isFirstScan)")
        // Always fetch recent stars on app startup (don't filter by lastStarAt)
        let newStars = try await api.fetchStargazers(repo: repoName, since: nil, totalStars: actualStarCount)
        NSLog("🔍 Got \(newStars.count) stars for \(repoName)")

        // Sort stars newest-first
        let sortedStars = newStars.sorted { $0.starredAt > $1.starredAt }

        // On first scan, only add the 10 most recent to avoid cluttering with old stars
        let starsToShow = isFirstScan ? Array(sortedStars.prefix(10)) : sortedStars

        for (index, star) in starsToShow.enumerated() {
          // Calculate star number (counting backwards from current total)
          let starNumber = actualStarCount - index

          // Add to recent stars (for menu display)
          // NEVER notify on initial scan - only webhooks should trigger notifications
          let event = StarEvent(
            repo: repoName,
            user: star.user.login,
            timestamp: star.starredAt,
            isRead: true,  // Always mark as read on scan (don't increment badge)
            starNumber: starNumber
          )
          recentStars.append(event)
        }

        // Update state
        if config?.state.repos[repoName] == nil {
          config?.state.repos[repoName] = RepoState(starCount: actualStarCount)
        } else {
          config?.state.repos[repoName]?.starCount = actualStarCount
        }

        if let mostRecent = sortedStars.first {
          config?.state.repos[repoName]?.lastStarAt = mostRecent.starredAt
        }
      }

      // Sort all recent stars newest-first and keep only last 50
      recentStars.sort { $0.timestamp > $1.timestamp }
      if recentStars.count > 50 {
        recentStars = Array(recentStars.prefix(50))
      }

      NSLog("🔍 performInitialScan: recentStars count = \(recentStars.count)")
      if recentStars.isEmpty {
        NSLog("⚠️ No recent stars found!")
      } else {
        NSLog("✓ Found \(recentStars.count) recent stars, newest: \(recentStars.first?.repo ?? "unknown")")
      }

      saveConfig()

      // Update menu on main thread
      DispatchQueue.main.async {
        NSLog("🔍 Updating menu with \(self.recentStars.count) stars")
        self.updateMenu()
      }
    } catch {
      NSLog("Scan error: \(error)")
    }

    DispatchQueue.main.async {
      self.setScanning(false)
      self.updateMenu()  // Update again to clear "Scanning..." status
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
    NSLog("✓ Network monitoring enabled")
  }

  func handleNetworkChange() async {
    NSLog("Network changed, restarting tunnel...")
    tunnelManager?.stop()
    webhookServer?.stop()
    await startTunnel()
  }

  func handleStarEvent(payload: WebhookPayload) {
    // Ignore ping/test webhooks (no action field)
    guard let action = payload.action, let sender = payload.sender else {
      NSLog("✓ Webhook ping received, ignoring")
      return
    }

    let repo = payload.repository.fullName

    // Add to tracked repos if new
    if !(config?.state.trackedRepos.contains(repo) ?? true) {
      config?.state.trackedRepos.append(repo)
    }

    // Update state
    if config?.state.repos[repo] == nil {
      config?.state.repos[repo] = RepoState(starCount: payload.repository.stargazersCount)
    }
    config?.state.repos[repo]?.lastStarAt = payload.starredAt ?? Date()
    config?.state.repos[repo]?.starCount = payload.repository.stargazersCount

    NSLog("📬 Webhook received: action=\(action), repo=\(repo), user=@\(sender.login)")

    if action == "started" {
      // New star (GitHub uses "started" for star events)
      NSLog("⭐ New star webhook received")
      let event = StarEvent(
        repo: repo,
        user: sender.login,
        timestamp: payload.starredAt ?? Date(),
        isRead: false,
        starNumber: payload.repository.stargazersCount
      )
      recentStars.insert(event, at: 0)

      // Keep only last 50
      if recentStars.count > 50 {
        recentStars = Array(recentStars.prefix(50))
      }

      NSLog("⭐ Showing notification for \(repo) from @\(sender.login)")
      notificationManager?.showStarNotification(repo: repo, user: sender.login)
      notificationManager?.incrementBadge()
      updateMenu()
      saveConfig()
      NSLog("⭐ Star notification sent!")
    } else if action == "deleted" {
      // Unstar - just update the count, don't show notification
      NSLog("⭐ Unstar: \(repo) by @\(sender.login)")
    }

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

  func isLaunchAtStartupEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return false
  }

  @objc func toggleLaunchAtStartup() {
    if #available(macOS 13.0, *) {
      do {
        if SMAppService.mainApp.status == .enabled {
          try SMAppService.mainApp.unregister()
        } else {
          try SMAppService.mainApp.register()
        }
        updateMenu()
      } catch {
        let alert = NSAlert()
        alert.messageText = "Could not toggle launch at startup"
        alert.informativeText = error.localizedDescription
        alert.runModal()
      }
    }
  }

  public func applicationWillTerminate(_ notification: Notification) {
    // Cleanup
    webhookServer?.stop()
    tunnelManager?.stop()
    networkMonitor?.stop()
    saveConfig()
  }
}
