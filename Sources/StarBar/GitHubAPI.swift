import Foundation

class GitHubAPI {
  private let token: String
  private let baseURL = "https://api.github.com"

  init(token: String) {
    self.token = token
  }

  func createRepoWebhook(repo: String, webhookURL: String) async throws -> Int {
    let url = URL(string: "\(baseURL)/repos/\(repo)/hooks")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let secret = UUID().uuidString
    let payload = WebhookCreateRequest(
      config: WebhookCreateRequest.WebhookConfig(
        url: webhookURL,
        secret: secret
      )
    )
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      NSLog("❌ createRepoWebhook: Not an HTTP response")
      throw APIError.requestFailed
    }

    if !(200...299).contains(httpResponse.statusCode) {
      let errorBody = String(data: data, encoding: .utf8) ?? "Unable to decode error"
      NSLog("❌ createRepoWebhook failed for \(repo): HTTP \(httpResponse.statusCode)")
      NSLog("❌ Response body: \(errorBody)")
      throw APIError.requestFailed
    }

    let webhookResponse = try JSONDecoder().decode(WebhookResponse.self, from: data)
    return webhookResponse.id
  }

  func deleteRepoWebhook(repo: String, webhookId: Int) async throws {
    let url = URL(string: "\(baseURL)/repos/\(repo)/hooks/\(webhookId)")!
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 204
    else {
      throw APIError.requestFailed
    }
  }

  func listRepoWebhooks(repo: String) async throws -> [WebhookResponse] {
    let url = URL(string: "\(baseURL)/repos/\(repo)/hooks")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode([WebhookResponse].self, from: data)
  }

  func getAuthenticatedUser() async throws -> String {
    let url = URL(string: "\(baseURL)/user")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

    let (data, _) = try await URLSession.shared.data(for: request)
    let user = try JSONDecoder().decode(GitHubUser.self, from: data)
    return user.login
  }

  func fetchRepos() async throws -> [GitHubRepo] {
    // Get authenticated user first
    let authenticatedUser = try await getAuthenticatedUser()

    var allRepos: [GitHubRepo] = []
    var page = 1

    while true {
      let url = URL(string: "\(baseURL)/user/repos?per_page=100&page=\(page)")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

      let (data, _) = try await URLSession.shared.data(for: request)
      let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)

      if repos.isEmpty { break }
      allRepos.append(contentsOf: repos)
      page += 1
    }

    // Filter to only repos YOU OWN with stars
    return allRepos.filter { $0.stargazersCount > 0 && $0.owner.login == authenticatedUser }
  }

  func fetchStargazers(repo: String, since: Date?, totalStars: Int = 0) async throws -> [Stargazer] {
    var allStargazers: [Stargazer] = []

    // Calculate which pages to fetch
    let startPage: Int
    let maxPagesToFetch: Int

    if since == nil && totalStars > 100 {
      // First scan: fetch last 5 pages (500 most recent stars)
      let totalPages = (totalStars + 99) / 100  // Round up
      startPage = max(1, totalPages - 4)  // Last 5 pages
      maxPagesToFetch = 5
    } else {
      // Incremental scan: start from page 1
      startPage = 1
      maxPagesToFetch = 100
    }

    var page = startPage
    var pagesFetched = 0

    while pagesFetched < maxPagesToFetch {
      let url = URL(string: "\(baseURL)/repos/\(repo)/stargazers?per_page=100&page=\(page)")!
      var request = URLRequest(url: url)
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")

      let (data, _) = try await URLSession.shared.data(for: request)

      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let stargazers = try decoder.decode([Stargazer].self, from: data)

      if stargazers.isEmpty { break }

      allStargazers.append(contentsOf: stargazers)

      // If we have a since date and found stars after it, we can stop
      if let since = since, stargazers.contains(where: { $0.starredAt > since }) {
        break
      }

      page += 1
      pagesFetched += 1
    }

    if let since = since {
      return allStargazers.filter { $0.starredAt > since }
    }

    return allStargazers
  }

  enum APIError: Error {
    case requestFailed
  }
}
