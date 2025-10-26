import Foundation

public class Config: Codable {
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
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let starbarDir = appSupport.appendingPathComponent("StarBar")
    try? FileManager.default.createDirectory(at: starbarDir, withIntermediateDirectories: true)
    return starbarDir.appendingPathComponent("config.json").path
  }
}
