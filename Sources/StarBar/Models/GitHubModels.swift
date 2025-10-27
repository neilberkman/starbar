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
  let action: String
  let repository: Repository
  let sender: GitHubUser
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
}
