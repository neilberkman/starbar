import Foundation
import Network

class WebhookServer {
  private var listener: NWListener?
  var onStarReceived: ((WebhookPayload) -> Void)?

  func start(port: UInt16 = 58472) throws {
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

    var receivedData = Data()

    func receiveMore() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        [weak self] data, _, isComplete, error in

        if let error = error {
          NSLog("❌ Connection error: \(error)")
          connection.cancel()
          return
        }

        if let data = data {
          receivedData.append(data)
        }

        // Parse HTTP request
        guard let request = String(data: receivedData, encoding: .utf8) else {
          if !isComplete {
            receiveMore()
          }
          return
        }

        // Check if we have complete HTTP request (headers + body)
        if let headerEnd = request.range(of: "\r\n\r\n") {
          // Extract Content-Length to know how much body to expect
          var expectedBodyLength = 0
          if let contentLengthRange = request.range(of: "Content-Length: "),
             let lineEnd = request[contentLengthRange.upperBound...].range(of: "\r\n") {
            let lengthString = request[contentLengthRange.upperBound..<lineEnd.lowerBound]
            expectedBodyLength = Int(lengthString) ?? 0
          }

          let headerEndIndex = request.distance(from: request.startIndex, to: headerEnd.upperBound)
          let bodyLength = receivedData.count - headerEndIndex

          // If we don't have the complete body yet, keep receiving
          if bodyLength < expectedBodyLength && !isComplete {
            receiveMore()
            return
          }

          // We have complete request, handle it
          if request.contains("POST /webhook") {
            let body = String(request[headerEnd.upperBound...])
            self?.handleWebhook(body: body)

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
        } else if !isComplete {
          // Don't have complete headers yet, keep receiving
          receiveMore()
        }
      }
    }

    receiveMore()
  }

  private func handleWebhook(body: String) {
    NSLog("🔌 handleWebhook called, body length: \(body.count)")

    // GitHub sends webhooks as application/x-www-form-urlencoded with payload= parameter
    var jsonString = body

    if body.hasPrefix("payload=") {
      // Extract and URL-decode the payload parameter
      let payloadValue = String(body.dropFirst("payload=".count))
      if let decoded = payloadValue.removingPercentEncoding {
        jsonString = decoded
        NSLog("🔌 Decoded URL-encoded payload")
      }
    }

    guard let data = jsonString.data(using: .utf8) else {
      NSLog("❌ Failed to convert body to data")
      return
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
      let payload = try decoder.decode(WebhookPayload.self, from: data)
      NSLog("✓ Decoded webhook payload successfully")
      onStarReceived?(payload)
    } catch {
      NSLog("❌ Failed to decode webhook payload: \(error)")
      NSLog("❌ JSON was: \(String(jsonString.prefix(500)))")
    }
  }
}
