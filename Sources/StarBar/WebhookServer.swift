import Foundation
import Network
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.xuku.starbar", category: "webhookserver")

class WebhookServer {
  private var listener: NWListener?
  private let listenerQueue = DispatchQueue(label: "com.starbar.webhook", qos: .userInitiated)
  var onStarReceived: ((WebhookPayload) -> Void)?
  var getWebhookSecret: ((String) -> String?)?  // Callback to get secret for repo

  func start(port: UInt16 = 63472) throws {
    // Stop existing listener if any
    if listener != nil {
      logger.warning("⚠️ Webhook server already exists, stopping old one first")
      stop()
    }

    logger.info("→ Creating NWListener on port \(port)")
    let params = NWParameters.tcp
    listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

    listener?.newConnectionHandler = { [weak self] connection in
      logger.info("→ New connection received")
      self?.handleConnection(connection)
    }

    logger.info("→ Starting listener on queue")
    listener?.start(queue: listenerQueue)
    logger.info("→ Listener.start() called")
  }

  func stop() {
    listener?.cancel()
    listener = nil
  }

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: listenerQueue)

    var receivedData = Data()

    func receiveMore() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        [weak self] data, _, isComplete, error in

        if let error = error {
          logger.error("❌ Connection error: \(error)")
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
            let headers = String(request[..<headerEnd.lowerBound])
            let body = String(request[headerEnd.upperBound...])
            self?.handleWebhook(headers: headers, body: body)

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

  private func handleWebhook(headers: String, body: String) {
    logger.debug("🔌 handleWebhook called, body length: \(body.count)")

    // GitHub sends webhooks as application/x-www-form-urlencoded with payload= parameter
    var jsonString = body

    if body.hasPrefix("payload=") {
      // Extract and URL-decode the payload parameter
      let payloadValue = String(body.dropFirst("payload=".count))
      if let decoded = payloadValue.removingPercentEncoding {
        jsonString = decoded
        logger.debug("🔌 Decoded URL-encoded payload")
      }
    }

    guard let data = jsonString.data(using: .utf8) else {
      logger.error("❌ Failed to convert body to data")
      return
    }

    // Save raw payload to file for test fixtures
    let timestamp = Date().timeIntervalSince1970
    let filename = "/tmp/webhook_\(timestamp).json"
    try? jsonString.write(toFile: filename, atomically: true, encoding: .utf8)
    logger.debug("💾 Saved raw webhook to: \(filename)")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
      let payload = try decoder.decode(WebhookPayload.self, from: data)
      logger.info("✓ Decoded webhook payload successfully")

      // Validate signature if we have a secret for this repo
      if let secret = getWebhookSecret?(payload.repository.fullName) {
        guard validateSignature(headers: headers, body: body, secret: secret) else {
          logger.error("❌ Invalid webhook signature for \(payload.repository.fullName) - rejecting webhook")
          return
        }
        logger.info("✓ Webhook signature validated for \(payload.repository.fullName)")
      } else {
        logger.warning("⚠️ No webhook secret found for \(payload.repository.fullName) - skipping validation")
      }

      onStarReceived?(payload)
    } catch {
      logger.error("❌ Failed to decode webhook payload: \(error)")
      logger.error("❌ JSON was: \(String(jsonString.prefix(500)))")
    }
  }

  private func validateSignature(headers: String, body: String, secret: String) -> Bool {
    // Extract X-Hub-Signature-256 header
    guard let signatureRange = headers.range(of: "X-Hub-Signature-256: ", options: .caseInsensitive),
          let lineEnd = headers[signatureRange.upperBound...].range(of: "\r\n") else {
      logger.error("❌ Missing X-Hub-Signature-256 header")
      return false
    }

    let receivedSignature = String(headers[signatureRange.upperBound..<lineEnd.lowerBound])
    logger.debug("🔐 Received signature: \(receivedSignature)")

    // GitHub sends the signature as "sha256=<hex>"
    guard receivedSignature.hasPrefix("sha256=") else {
      logger.error("❌ Invalid signature format")
      return false
    }

    let receivedHex = String(receivedSignature.dropFirst("sha256=".count))

    // Compute HMAC-SHA256 of the raw body
    guard let bodyData = body.data(using: .utf8),
          let secretData = secret.data(using: .utf8) else {
      logger.error("❌ Failed to convert body or secret to data")
      return false
    }

    let key = SymmetricKey(data: secretData)
    let signature = HMAC<SHA256>.authenticationCode(for: bodyData, using: key)
    let computedHex = signature.map { String(format: "%02x", $0) }.joined()

    logger.debug("🔐 Computed signature: sha256=\(computedHex)")

    // Constant-time comparison
    return receivedHex.lowercased() == computedHex.lowercased()
  }
}
