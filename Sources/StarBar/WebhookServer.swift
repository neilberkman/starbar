import Foundation
import Network

class WebhookServer {
  private var listener: NWListener?
  var onStarReceived: ((WebhookPayload) -> Void)?

  func start(port: UInt16 = 3000) throws {
    let params = NWParameters.tcp
    listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

    listener?.newConnectionHandler = { [weak self] connection in
      self?.handleConnection(connection)
    }

    listener?.start(queue: .main)
  }

  func stop() {
    listener?.cancel()
    listener = nil
  }

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: .main)

    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
      [weak self] data, _, isComplete, error in
      guard let data = data, !data.isEmpty else { return }

      // Parse HTTP request
      let request = String(data: data, encoding: .utf8) ?? ""

      if request.contains("POST /webhook") {
        // Extract body from HTTP request
        if let bodyStart = request.range(of: "\r\n\r\n")?.upperBound {
          let body = String(request[bodyStart...])
          self?.handleWebhook(body: body)
        }

        // Send 200 OK
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
        connection.send(
          content: response.data(using: .utf8),
          completion: .contentProcessed({ _ in
            connection.cancel()
          }))
      } else if request.contains("GET /health") {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
        connection.send(
          content: response.data(using: .utf8),
          completion: .contentProcessed({ _ in
            connection.cancel()
          }))
      } else {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
        connection.send(
          content: response.data(using: .utf8),
          completion: .contentProcessed({ _ in
            connection.cancel()
          }))
      }
    }
  }

  private func handleWebhook(body: String) {
    guard let data = body.data(using: .utf8) else { return }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let payload = try? decoder.decode(WebhookPayload.self, from: data) {
      onStarReceived?(payload)
    }
  }
}
