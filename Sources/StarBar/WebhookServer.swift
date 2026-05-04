import Foundation
import Network
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.xuku.starbar", category: "webhookserver")

class WebhookServer {
  private var listener: NWListener?
  private let listenerQueue = DispatchQueue(label: "com.starbar.webhook", qos: .userInitiated)
  var onStarReceived: ((WebhookPayload) -> Void)?
  var onIssueEvent: ((IssuePayload) -> Void)?
  var onPullRequestEvent: ((PullRequestPayload) -> Void)?
  var getWebhookSecret: ((String) -> String?)?

  func start(port: UInt16 = 63472) throws {
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

        guard let request = String(data: receivedData, encoding: .utf8) else {
          if !isComplete {
            receiveMore()
          }
          return
        }

        if let headerEnd = request.range(of: "\r\n\r\n") {
          var expectedBodyLength = 0
          if let contentLengthRange = request.range(of: "Content-Length: "),
             let lineEnd = request[contentLengthRange.upperBound...].range(of: "\r\n") {
            let lengthString = request[contentLengthRange.upperBound..<lineEnd.lowerBound]
            expectedBodyLength = Int(lengthString) ?? 0
          }

          let headerEndIndex = request.distance(from: request.startIndex, to: headerEnd.upperBound)
          let bodyLength = receivedData.count - headerEndIndex

          if bodyLength < expectedBodyLength && !isComplete {
            receiveMore()
            return
          }

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
          receiveMore()
        }
      }
    }

    receiveMore()
  }

  private func handleWebhook(headers: String, body: String) {
    logger.debug("🔌 handleWebhook called, body length: \(body.count)")

    var jsonString = body
    if body.hasPrefix("payload=") {
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

    let timestamp = Date().timeIntervalSince1970
    let filename = "/tmp/webhook_\(timestamp).json"
    try? jsonString.write(toFile: filename, atomically: true, encoding: .utf8)
    logger.debug("💾 Saved raw webhook to: \(filename)")

    let event = headerValue(named: "X-GitHub-Event", in: headers)?.lowercased() ?? ""
    logger.info("📬 Webhook event: \(event)")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // Extract repo name for signature secret lookup, regardless of event shape.
    guard let envelope = try? decoder.decode(WebhookEnvelope.self, from: data) else {
      // ping events have repository too; only events without one (e.g. installation pings) hit this
      logger.warning("⚠️ Could not extract repository from webhook body")
      return
    }
    let repoName = envelope.repository.fullName

    if let secret = getWebhookSecret?(repoName) {
      guard validateSignature(headers: headers, body: jsonString, secret: secret) else {
        logger.error("❌ Invalid webhook signature for \(repoName) - rejecting")
        return
      }
      logger.info("✓ Webhook signature validated for \(repoName)")
    } else {
      logger.warning("⚠️ No webhook secret for \(repoName) - skipping validation")
    }

    switch event {
    case "ping":
      logger.info("✓ Ping received for \(repoName)")
    case "watch":
      decodeAndDispatch(WebhookPayload.self, from: data, decoder: decoder) { [weak self] payload in
        self?.onStarReceived?(payload)
      }
    case "issues":
      decodeAndDispatch(IssuePayload.self, from: data, decoder: decoder) { [weak self] payload in
        self?.onIssueEvent?(payload)
      }
    case "pull_request":
      decodeAndDispatch(PullRequestPayload.self, from: data, decoder: decoder) { [weak self] payload in
        self?.onPullRequestEvent?(payload)
      }
    default:
      logger.info("ℹ️ Ignoring webhook event: \(event)")
    }
  }

  private func decodeAndDispatch<T: Decodable>(
    _ type: T.Type, from data: Data, decoder: JSONDecoder, dispatch: (T) -> Void
  ) {
    do {
      let payload = try decoder.decode(T.self, from: data)
      dispatch(payload)
    } catch {
      logger.error("❌ Failed to decode \(String(describing: T.self)): \(error)")
    }
  }

  private func headerValue(named name: String, in headers: String) -> String? {
    guard let range = headers.range(of: "\(name): ", options: .caseInsensitive),
          let lineEnd = headers[range.upperBound...].range(of: "\r\n") else {
      return nil
    }
    return String(headers[range.upperBound..<lineEnd.lowerBound])
  }

  private func validateSignature(headers: String, body: String, secret: String) -> Bool {
    guard let signatureRange = headers.range(of: "X-Hub-Signature-256: ", options: .caseInsensitive),
          let lineEnd = headers[signatureRange.upperBound...].range(of: "\r\n") else {
      logger.error("❌ Missing X-Hub-Signature-256 header")
      return false
    }

    let receivedSignature = String(headers[signatureRange.upperBound..<lineEnd.lowerBound])
    logger.debug("🔐 Received signature: \(receivedSignature)")

    guard receivedSignature.hasPrefix("sha256=") else {
      logger.error("❌ Invalid signature format")
      return false
    }

    let receivedHex = String(receivedSignature.dropFirst("sha256=".count))

    guard let bodyData = body.data(using: .utf8),
          let secretData = secret.data(using: .utf8) else {
      logger.error("❌ Failed to convert body or secret to data")
      return false
    }

    let key = SymmetricKey(data: secretData)
    let signature = HMAC<SHA256>.authenticationCode(for: bodyData, using: key)
    let computedHex = signature.map { String(format: "%02x", $0) }.joined()

    logger.debug("🔐 Computed signature: sha256=\(computedHex)")

    return receivedHex.lowercased() == computedHex.lowercased()
  }
}
