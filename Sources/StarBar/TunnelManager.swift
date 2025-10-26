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
        !data.isEmpty
      {
        output += String(data: data, encoding: .utf8) ?? ""

        if let url = Self.parseURL(from: output) {
          tunnelURL = url
          return url
        }
      }

      try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
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
