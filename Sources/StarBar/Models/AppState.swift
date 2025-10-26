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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lastFullScan = try container.decodeIfPresent(Date.self, forKey: .lastFullScan)
    scanIntervalDays = try container.decode(Int.self, forKey: .scanIntervalDays)
    userWebhookId = try container.decodeIfPresent(Int.self, forKey: .userWebhookId)
    trackedRepos = try container.decode([String].self, forKey: .trackedRepos)
    repos = try container.decodeIfPresent([String: RepoState].self, forKey: .repos) ?? [:]
  }
}

struct RepoState: Codable {
  var lastStarAt: Date?
  var starCount: Int
  var webhookSecret: String?

  enum CodingKeys: String, CodingKey {
    case lastStarAt = "last_star_at"
    case starCount = "star_count"
    case webhookSecret = "webhook_secret"
  }
}
