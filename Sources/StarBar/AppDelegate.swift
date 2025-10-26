import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem?
  var config: Config?
  var tunnelManager: TunnelManager?
  var webhookServer: WebhookServer?
  var gitHubAPI: GitHubAPI?
  var notificationManager: NotificationManager?
  var networkMonitor: NetworkMonitor?

  public override init() {
    super.init()
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
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
    menu.addItem(
      NSMenuItem(title: "Rescan Repos Now", action: #selector(rescanRepos), keyEquivalent: "r"))
    menu.addItem(NSMenuItem(title: "Clear Badge", action: #selector(clearBadge), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
    alert.informativeText =
      "Enter your GitHub token to get started.\n\nCreate one at:\nhttps://github.com/settings/tokens/new?scopes=repo,admin:repo_hook"
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
    if !(config?.state.trackedRepos.contains(repo) ?? true) {
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

  public func applicationWillTerminate(_ notification: Notification) {
    // Cleanup
    webhookServer?.stop()
    tunnelManager?.stop()
    networkMonitor?.stop()
    saveConfig()
  }
}
