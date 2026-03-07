import Foundation
import os.log

private let logger = Logger(subsystem: "com.xuku.starbar", category: "tunnel")

class TunnelManager {
  private static let commonNgrokPaths = [
    "/opt/homebrew/bin/ngrok",  // Apple Silicon Homebrew
    "/usr/local/bin/ngrok",     // Intel Homebrew
    "/usr/bin/ngrok",           // System install
  ]

  private var process: Process?
  private(set) var tunnelURL: String?
  private var outputPipe = Pipe()
  private var errorPipe = Pipe()
  private var stdoutBuffer = Data()
  private var stderrBuffer = Data()
  private var startupFailure: TunnelError?
  private var recentLogLines: [String] = []
  private var isStarting = false
  private var isStopping = false
  var onTunnelURLChanged: ((String) -> Void)?
  var onTunnelDied: (() -> Void)?

  static func parseURL(from output: String) -> String? {
    let pattern = #"https://[A-Za-z0-9-]+\.(?:ngrok(?:-free)?\.app|trycloudflare\.com)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

    let range = NSRange(output.startIndex..., in: output)
    guard let match = regex.firstMatch(in: output, range: range),
          let matchRange = Range(match.range, in: output)
    else {
      return nil
    }

    return String(output[matchRange])
  }

  func start(port: Int = 63472, timeout: TimeInterval = 10, maxRetries: Int = 3) async throws -> String {
    guard !isStarting else {
      logger.warning("⚠️ Tunnel already starting, skipping duplicate start request")
      throw TunnelError.alreadyStarting
    }

    isStarting = true
    defer { isStarting = false }

    var lastError: Error?

    for attempt in 1...maxRetries {
      do {
        let url = try await attemptStart(port: port, timeout: timeout)
        if attempt > 1 {
          logger.info("✓ Tunnel recovered after \(attempt) attempts")
        }
        return url
      } catch {
        lastError = error
        logger.warning("⚠️ Tunnel attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")
        stop()

        if attempt < maxRetries {
          let backoffSeconds = min(pow(2.0, Double(attempt)), 10.0)
          logger.info("→ Retrying in \(backoffSeconds)s...")
          try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }
      }
    }

    throw lastError ?? TunnelError.urlParseTimeout
  }

  private func attemptStart(port: Int, timeout: TimeInterval) async throws -> String {
    let ngrokPath = try findNgrokPath()

    stop()
    isStopping = false
    startupFailure = nil
    tunnelURL = nil
    stdoutBuffer.removeAll(keepingCapacity: false)
    stderrBuffer.removeAll(keepingCapacity: false)
    recentLogLines.removeAll(keepingCapacity: false)

    outputPipe = Pipe()
    errorPipe = Pipe()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: ngrokPath)
    process.arguments = [
      "http",
      "\(port)",
      "--log", "stdout",
      "--log-format", "json",
      "--log-level", "info",
    ]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }

      self?.consumeOutput(data, isErrorStream: false)
    }

    errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }

      self?.consumeOutput(data, isErrorStream: true)
    }

    process.terminationHandler = { [weak self] proc in
      guard let self = self else { return }

      let reason = proc.terminationReason
      let status = proc.terminationStatus
      logger.error("💀 Ngrok terminated: reason=\(reason.rawValue) status=\(status)")

      self.cleanupStreamReaders()

      if self.isStopping {
        self.isStopping = false
        return
      }

      if self.tunnelURL == nil {
        self.startupFailure = .processExited(self.latestLogSummary(status: status))
      } else {
        self.tunnelURL = nil
        self.onTunnelDied?()
      }
    }

    self.process = process
    try process.run()
    logger.info("→ Started ngrok at: \(ngrokPath)")

    let startTime = Date()
    while Date().timeIntervalSince(startTime) < timeout {
      if let url = tunnelURL {
        return url
      }

      if let startupFailure {
        throw startupFailure
      }

      if !process.isRunning {
        throw TunnelError.processExited(latestLogSummary(status: process.terminationStatus))
      }

      try await Task.sleep(nanoseconds: 200_000_000)
    }

    throw TunnelError.urlParseTimeout
  }

  func stop() {
    isStopping = true
    startupFailure = nil
    tunnelURL = nil
    stdoutBuffer.removeAll(keepingCapacity: false)
    stderrBuffer.removeAll(keepingCapacity: false)
    recentLogLines.removeAll(keepingCapacity: false)

    cleanupStreamReaders()

    let process = self.process
    self.process = nil
    process?.terminationHandler = nil

    guard let process, process.isRunning else {
      isStopping = false
      return
    }

    process.terminate()
    process.waitUntilExit()
    isStopping = false
  }

  private func findNgrokPath() throws -> String {
    for path in Self.commonNgrokPaths where FileManager.default.fileExists(atPath: path) {
      return path
    }

    throw TunnelError.ngrokNotInstalled
  }

  private func consumeOutput(_ data: Data, isErrorStream: Bool) {
    if isErrorStream {
      stderrBuffer.append(data)
      drainBuffer(&stderrBuffer)
    } else {
      stdoutBuffer.append(data)
      drainBuffer(&stdoutBuffer)
    }
  }

  private func drainBuffer(_ buffer: inout Data) {
    while let newlineIndex = buffer.firstIndex(of: 0x0a) {
      let lineData = buffer.prefix(upTo: newlineIndex)
      buffer.removeSubrange(...newlineIndex)

      guard let rawLine = String(data: lineData, encoding: .utf8) else { continue }
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }

      recentLogLines.append(line)
      if recentLogLines.count > 20 {
        recentLogLines.removeFirst(recentLogLines.count - 20)
      }

      if let url = Self.parseURL(from: line), url != tunnelURL {
        tunnelURL = url
        logger.info("✓ Tunnel URL extracted from ngrok logs: \(url)")
        onTunnelURLChanged?(url)
      }
    }
  }

  private func latestLogSummary(status: Int32) -> String {
    let recentLogs = recentLogLines.suffix(3).joined(separator: " | ")
    if recentLogs.isEmpty {
      return "status \(status)"
    }

    return "status \(status): \(recentLogs)"
  }

  private func cleanupStreamReaders() {
    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil
  }

  enum TunnelError: Error, LocalizedError {
    case ngrokNotInstalled
    case urlParseTimeout
    case alreadyStarting
    case processExited(String)

    var errorDescription: String? {
      switch self {
      case .ngrokNotInstalled:
        return "ngrok not found. Please install it: brew install ngrok && ngrok config add-authtoken YOUR_TOKEN"
      case .urlParseTimeout:
        return "Failed to get tunnel URL from ngrok before timeout. Check your ngrok config and auth token."
      case .alreadyStarting:
        return "Tunnel is already starting"
      case .processExited(let details):
        return "ngrok exited before the tunnel was ready (\(details))"
      }
    }
  }
}
