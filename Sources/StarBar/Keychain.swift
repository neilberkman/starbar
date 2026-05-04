import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.xuku.starbar", category: "keychain")

enum Keychain {
  static var defaultService = "com.xuku.starbar"
  static var defaultAccount = "github_token"

  static func setToken(_ token: String, service: String = defaultService, account: String = defaultAccount) throws {
    let data = Data(token.utf8)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let updateAttrs: [String: Any] = [
      kSecValueData as String: data,
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)

    if updateStatus == errSecItemNotFound {
      var addAttrs = query
      addAttrs[kSecValueData as String] = data
      addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        logger.error("❌ Keychain SecItemAdd failed: \(addStatus)")
        throw KeychainError.unhandledStatus(addStatus)
      }
    } else if updateStatus != errSecSuccess {
      logger.error("❌ Keychain SecItemUpdate failed: \(updateStatus)")
      throw KeychainError.unhandledStatus(updateStatus)
    }
  }

  static func getToken(service: String = defaultService, account: String = defaultAccount) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      if status != errSecItemNotFound {
        logger.error("❌ Keychain SecItemCopyMatching failed: \(status)")
      }
      return nil
    }

    guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
      return nil
    }
    return token
  }

  @discardableResult
  static func deleteToken(service: String = defaultService, account: String = defaultAccount) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  enum KeychainError: Error {
    case unhandledStatus(OSStatus)
  }
}
