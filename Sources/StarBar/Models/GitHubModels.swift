import Foundation

struct GitHubRepo: Codable {
  let fullName: String
  let stargazersCount: Int
  let owner: RepoOwner

  struct RepoOwner: Codable {
    let login: String
  }

  enum CodingKeys: String, CodingKey {
    case fullName = "full_name"
    case stargazersCount = "stargazers_count"
    case owner
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
  let action: String?  // Optional: ping events don't have this
  let repository: Repository
  let sender: GitHubUser?  // Optional: ping events don't have this
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

  // Custom decoding to handle missing keys (ping events)
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    action = try container.decodeIfPresent(String.self, forKey: .action)
    repository = try container.decode(Repository.self, forKey: .repository)
    sender = try container.decodeIfPresent(GitHubUser.self, forKey: .sender)
    starredAt = try container.decodeIfPresent(Date.self, forKey: .starredAt)
  }

  // Custom encoding
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(action, forKey: .action)
    try container.encode(repository, forKey: .repository)
    try container.encodeIfPresent(sender, forKey: .sender)
    try container.encodeIfPresent(starredAt, forKey: .starredAt)
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
  let config: WebhookConfig

  struct WebhookConfig: Codable {
    let url: String
  }
}
