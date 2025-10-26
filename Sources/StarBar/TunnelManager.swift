import Foundation

class TunnelManager {
  private var process: Process?
  private(set) var tunnelURL: String?
  private var outputPipe = Pipe()
  private var errorPipe = Pipe()
  private var healthCheckTask: Task<Void, Never>?
  private var isStarting = false
  var onTunnelURLChanged: ((String) -> Void)?
  var onTunnelDied: (() -> Void)?

  static func parseURL(from output: String) -> String? {
    // ngrok outputs: url=https://xxxx.ngrok-free.app
    let pattern = "https://[a-zA-Z0-9-]+\\.ngrok-free\\.app"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

    let range = NSRange(output.startIndex..., in: output)
    guard let match = regex.firstMatch(in: output, range: range) else { return nil }

    return String(output[Range(match.range, in: output)!])
  }

  func start(port: Int = 63472, timeout: TimeInterval = 10, maxRetries: Int = 3) async throws -> String {
    // Prevent concurrent starts
    guard !isStarting else {
      NSLog("⚠️ Tunnel already starting, skipping duplicate start request")
      throw TunnelError.alreadyStarting
    }
    isStarting = true
    defer { isStarting = false }

    // Try with exponential backoff
    var lastError: Error?

    for attempt in 1...maxRetries {
      do {
        let url = try await attemptStart(port: port, timeout: timeout)
        if attempt > 1 {
          NSLog("✓ Tunnel recovered after \(attempt) attempts")
        }
        return url
      } catch {
        lastError = error
        NSLog("⚠️ Tunnel attempt \(attempt)/\(maxRetries) failed: \(error)")

        if attempt < maxRetries {
          // Exponential backoff: 2s, 4s, 8s
          let backoffSeconds = min(pow(2.0, Double(attempt)), 10.0)
          NSLog("→ Retrying in \(backoffSeconds)s...")
          try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }
      }
    }

    throw lastError ?? TunnelError.urlParseTimeout
  }

  private func attemptStart(port: Int, timeout: TimeInterval) async throws -> String {
    // Check if ngrok is installed and get its path
    let checkProcess = Process()
    checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    checkProcess.arguments = ["ngrok"]

    let whichPipe = Pipe()
    checkProcess.standardOutput = whichPipe

    try checkProcess.run()
    checkProcess.waitUntilExit()

    guard checkProcess.terminationStatus == 0 else {
      throw TunnelError.ngrokNotInstalled
    }

    // Get ngrok path from which output
    let whichData = whichPipe.fileHandleForReading.readDataToEndOfFile()
    let ngrokPath = String(data: whichData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "ngrok"
    NSLog("→ Found ngrok at: \(ngrokPath)")

    // Clean up any orphaned ngrok tunnels from previous runs on this port
    let cleanupProcess = Process()
    cleanupProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    cleanupProcess.arguments = ["-f", "ngrok http \(port)"]
    try? cleanupProcess.run()
    cleanupProcess.waitUntilExit()

    // Give it a moment to clean up
    try await Task.sleep(nanoseconds: 500_000_000)  // 500ms

    // Create fresh pipes for each attempt
    outputPipe = Pipe()
    errorPipe = Pipe()

    // Start tunnel using discovered path
    process = Process()
    process?.executableURL = URL(fileURLWithPath: ngrokPath)
    process?.arguments = ["http", "\(port)"]

    process?.standardOutput = outputPipe
    process?.standardError = errorPipe

    // Setup termination handler - called automatically when process exits
    process?.terminationHandler = { [weak self] proc in
      let reason = proc.terminationReason
      let status = proc.terminationStatus
      NSLog("💀 Ngrok terminated: reason=\(reason.rawValue) status=\(status)")

      // Restart on ANY termination - we always want the tunnel running
      self?.onTunnelDied?()
    }

    try process?.run()

    // Wait for ngrok to start and query its API
    try await Task.sleep(nanoseconds: 2_000_000_000)  // 2s for ngrok to start

    // Try both common ngrok API ports (4040 is default, but it may use 4041 if 4040 is busy)
    let apiPorts = [4040, 4041]

    let startTime = Date()
    while Date().timeIntervalSince(startTime) < timeout {
      for port in apiPorts {
        guard let apiURL = URL(string: "http://localhost:\(port)/api/tunnels") else { continue }

        do {
          let (data, _) = try await URLSession.shared.data(from: apiURL)
          if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
             let tunnels = json["tunnels"] as? [[String: Any]],
             let firstTunnel = tunnels.first,
             let publicURL = firstTunnel["public_url"] as? String,
             publicURL.hasPrefix("https://")
          {
            tunnelURL = publicURL
            NSLog("✓ Tunnel URL extracted from API (port \(port)): \(publicURL)")

            // Start health monitoring
            startHealthMonitoring()

            // Notify callback that URL is ready
            onTunnelURLChanged?(publicURL)

            return publicURL
          }
        } catch {
          // API not ready on this port, try next
          continue
        }
      }

      try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
    }

    NSLog("❌ Tunnel URL fetch timeout after \(timeout)s")
    throw TunnelError.urlParseTimeout
  }

  // Ngrok URLs don't change once started, so no need to monitor for changes

  private func startHealthMonitoring() {
    healthCheckTask?.cancel()

    healthCheckTask = Task {
      // Check every 60s if process is still alive
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s

        guard let proc = process, !proc.isRunning else {
          if process != nil {
            NSLog("💀 Ngrok process died")
            onTunnelDied?()
          }
          break
        }
      }
    }
  }

  func stop() {
    process?.terminationHandler = nil
    healthCheckTask?.cancel()
    healthCheckTask = nil
    process?.terminate()
    process = nil
    tunnelURL = nil
  }

  enum TunnelError: Error {
    case ngrokNotInstalled
    case urlParseTimeout
    case alreadyStarting
  }
}
