import Foundation
import os.log

private let logger = Logger(subsystem: "com.xuku.starbar", category: "config")

public class Config: Codable {
  var githubToken: String
  var state: AppState

  enum CodingKeys: String, CodingKey {
    case githubToken = "github_token"  // legacy: read for migration only, never written
    case state
  }

  init(githubToken: String = "", state: AppState = AppState()) {
    self.githubToken = githubToken
    self.state = state
  }

  public required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    state = try container.decode(AppState.self, forKey: .state)
    githubToken = try container.decodeIfPresent(String.self, forKey: .githubToken) ?? ""
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(state, forKey: .state)
    // githubToken intentionally omitted — stored in Keychain
  }

  static func load(from path: String) -> Config? {
    var loaded: Config?
    var legacyToken: String?

    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      loaded = try? decoder.decode(Config.self, from: data)
      if let token = loaded?.githubToken, !token.isEmpty {
        legacyToken = token
      }
    }

    let keychainToken = Keychain.getToken()

    if loaded == nil && (keychainToken?.isEmpty ?? true) && legacyToken == nil {
      return nil
    }

    let cfg = loaded ?? Config()

    if let kt = keychainToken, !kt.isEmpty {
      cfg.githubToken = kt
      // If JSON still carries a legacy token, scrub it.
      if legacyToken != nil {
        try? cfg.save(to: path)
      }
    } else if let lt = legacyToken {
      do {
        try Keychain.setToken(lt)
        logger.info("✓ Migrated GitHub token from JSON to Keychain")
        cfg.githubToken = lt
        try cfg.save(to: path)  // scrubs token from JSON
      } catch {
        logger.error("❌ Keychain migration failed, leaving token in JSON: \(error)")
        cfg.githubToken = lt
      }
    } else {
      cfg.githubToken = ""
    }

    return cfg
  }

  func save(to path: String) throws {
    if !githubToken.isEmpty {
      try Keychain.setToken(githubToken)
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(self)
    try data.write(to: URL(fileURLWithPath: path))
  }

  static var defaultPath: String {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let starbarDir = appSupport.appendingPathComponent("StarBar")
    try? FileManager.default.createDirectory(at: starbarDir, withIntermediateDirectories: true)
    return starbarDir.appendingPathComponent("config.json").path
  }
}
