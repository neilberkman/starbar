#!/usr/bin/env swift
import Foundation
import CryptoKit

// Usage: ./send_test_webhook.swift <tunnel_url> <secret>
guard CommandLine.arguments.count == 3 else {
    print("Usage: ./send_test_webhook.swift <tunnel_url> <secret>")
    print("Example: ./send_test_webhook.swift https://xyz.trycloudflare.com my-secret-123")
    exit(1)
}

let tunnelURL = CommandLine.arguments[1]
let secret = CommandLine.arguments[2]

// Create test payload (GitHub star webhook format)
let payload = """
{
  "action": "started",
  "starred_at": "\(ISO8601DateFormatter().string(from: Date()))",
  "repository": {
    "full_name": "test/repo",
    "stargazers_count": 42
  },
  "sender": {
    "login": "test-user"
  }
}
"""

print("📤 Sending test webhook to: \(tunnelURL)/webhook")
print("🔐 Using secret: \(secret)")
print("📦 Payload:")
print(payload)
print()

// Compute HMAC signature
guard let payloadData = payload.data(using: .utf8),
      let secretData = secret.data(using: .utf8) else {
    print("❌ Failed to encode payload or secret")
    exit(1)
}

let key = SymmetricKey(data: secretData)
let hmac = HMAC<SHA256>.authenticationCode(for: payloadData, using: key)
let signature = "sha256=" + hmac.map { String(format: "%02x", $0) }.joined()

print("🔐 Computed signature: \(signature)\n")

// Send webhook request
guard let url = URL(string: "\(tunnelURL)/webhook") else {
    print("❌ Invalid URL")
    exit(1)
}

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue(signature, forHTTPHeaderField: "X-Hub-Signature-256")
request.setValue("GitHub-Hookshot/test", forHTTPHeaderField: "User-Agent")
request.httpBody = payloadData

let semaphore = DispatchSemaphore(value: 0)

URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }

    if let error = error {
        print("❌ Request failed: \(error.localizedDescription)")
        return
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        print("❌ Invalid response")
        return
    }

    print("📥 Response: HTTP \(httpResponse.statusCode)")

    if let data = data, let body = String(data: data, encoding: .utf8) {
        print("📥 Body: \(body)")
    }

    if httpResponse.statusCode == 200 {
        print("✅ Webhook delivered successfully!")
    } else {
        print("⚠️ Unexpected status code")
    }
}.resume()

semaphore.wait()
