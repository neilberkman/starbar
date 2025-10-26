import Foundation

class GitHubAPI {
    private let token: String
    private let baseURL = "https://api.github.com"

    init(token: String) {
        self.token = token
    }

    func createWebhookRequest(username: String, webhookURL: String) -> URLRequest {
        let url = URL(string: "\(baseURL)/users/\(username)/hooks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        return request
    }

    func createWebhook(username: String, webhookURL: String) async throws -> Int {
        let secret = UUID().uuidString
        let payload = WebhookCreateRequest(
            config: WebhookCreateRequest.WebhookConfig(
                url: webhookURL,
                secret: secret
            )
        )

        var request = createWebhookRequest(username: username, webhookURL: webhookURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        let webhookResponse = try JSONDecoder().decode(WebhookResponse.self, from: data)
        return webhookResponse.id
    }

    func deleteWebhook(username: String, webhookId: Int) async throws {
        let url = URL(string: "\(baseURL)/users/\(username)/hooks/\(webhookId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw APIError.requestFailed
        }
    }

    func listWebhooks(username: String) async throws -> [WebhookResponse] {
        let url = URL(string: "\(baseURL)/users/\(username)/hooks")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([WebhookResponse].self, from: data)
    }

    func fetchRepos() async throws -> [GitHubRepo] {
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

        return allRepos.filter { $0.stargazersCount > 0 }
    }

    func fetchStargazers(repo: String, since: Date?) async throws -> [Stargazer] {
        let url = URL(string: "\(baseURL)/repos/\(repo)/stargazers?per_page=100")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.star+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stargazers = try decoder.decode([Stargazer].self, from: data)

        if let since = since {
            return stargazers.filter { $0.starredAt > since }
        }

        return stargazers
    }

    enum APIError: Error {
        case requestFailed
    }
}
