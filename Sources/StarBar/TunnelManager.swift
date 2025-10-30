import Foundation

class TunnelManager {
  private var process: Process?
  private(set) var tunnelURL: String?
  private var outputPipe = Pipe()
  private var errorPipe = Pipe()
  var onTunnelURLChanged: ((String) -> Void)?
  var onTunnelDied: (() -> Void)?

  static func parseURL(from output: String) -> String? {
    let pattern = "https://[a-zA-Z0-9-]+\\.trycloudflare\\.com"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

    let range = NSRange(output.startIndex..., in: output)
    guard let match = regex.firstMatch(in: output, range: range) else { return nil }

    return String(output[Range(match.range, in: output)!])
  }

  func start(port: Int = 58472, timeout: TimeInterval = 10, maxRetries: Int = 3) async throws -> String {
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
    // Check if cloudflared is installed
    let checkProcess = Process()
    checkProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    checkProcess.arguments = ["cloudflared"]

    try checkProcess.run()
    checkProcess.waitUntilExit()

    guard checkProcess.terminationStatus == 0 else {
      throw TunnelError.cloudflaredNotInstalled
    }

    // Clean up any orphaned cloudflared tunnels from previous runs on this port
    let cleanupProcess = Process()
    cleanupProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    cleanupProcess.arguments = ["-f", "cloudflared tunnel --url http://localhost:\(port)"]
    try? cleanupProcess.run()
    cleanupProcess.waitUntilExit()

    // Give it a moment to clean up
    try await Task.sleep(nanoseconds: 500_000_000)  // 500ms

    // Create fresh pipes for each attempt
    outputPipe = Pipe()
    errorPipe = Pipe()

    // Start tunnel
    process = Process()
    process?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cloudflared")
    process?.arguments = ["tunnel", "--url", "http://localhost:\(port)"]

    process?.standardOutput = outputPipe
    process?.standardError = errorPipe

    // Setup termination handler - called automatically when process exits
    process?.terminationHandler = { [weak self] proc in
      if proc.terminationStatus != 0 {
        NSLog("❌ Cloudflared crashed (exit code: \(proc.terminationStatus))")
        self?.onTunnelDied?()
      }
    }

    try process?.run()

    // Parse URL from output with timeout
    // cloudflared writes to stderr, not stdout
    let startTime = Date()
    var output = ""

    while Date().timeIntervalSince(startTime) < timeout {
      // Read from errorPipe since cloudflared writes to stderr
      if let data = try? errorPipe.fileHandleForReading.availableData,
        !data.isEmpty
      {
        output += String(data: data, encoding: .utf8) ?? ""

        if let url = Self.parseURL(from: output) {
          tunnelURL = url
          NSLog("✓ Tunnel URL extracted: \(url)")

          // Start continuous monitoring for URL changes
          Task {
            await monitorTunnelURLChanges()
          }

          return url
        }
      }

      try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
    }

    NSLog("❌ Tunnel URL parse timeout after \(timeout)s")
    throw TunnelError.urlParseTimeout
  }

  private func monitorTunnelURLChanges() async {
    NSLog("→ Started monitoring cloudflared for tunnel URL changes")
    var buffer = ""

    while process?.isRunning == true {
      // Read any new output from cloudflared
      if let data = try? errorPipe.fileHandleForReading.availableData,
         !data.isEmpty
      {
        if let newOutput = String(data: data, encoding: .utf8) {
          buffer += newOutput

          // Look for new tunnel URL in the output
          if let newURL = Self.parseURL(from: buffer) {
            if newURL != tunnelURL {
              NSLog("🔄 Detected tunnel URL change: \(tunnelURL ?? "nil") -> \(newURL)")
              tunnelURL = newURL
              onTunnelURLChanged?(newURL)
              buffer = ""  // Clear buffer after finding URL
            }
          }

          // Keep buffer from growing too large
          if buffer.count > 10000 {
            buffer = String(buffer.suffix(5000))
          }
        }
      }

      try? await Task.sleep(nanoseconds: 500_000_000)  // Check every 500ms
    }

    NSLog("→ Stopped monitoring cloudflared (process ended)")
  }

  func stop() {
    process?.terminationHandler = nil
    process?.terminate()
    process = nil
    tunnelURL = nil
  }

  enum TunnelError: Error {
    case cloudflaredNotInstalled
    case urlParseTimeout
  }
}
