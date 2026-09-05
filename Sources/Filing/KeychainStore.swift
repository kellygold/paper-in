import Foundation
import Security

enum KeychainStore {
  static let service = "Paper In AI providers"
  static func read(_ account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw PaperError("Couldn’t read the API key from Keychain (\(status)).")
    }
    return String(data: data, encoding: .utf8)
  }
  static func save(_ value: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if value.isEmpty {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw PaperError("Couldn’t remove the API key.")
      }
      return
    }
    let attributes = [kSecValueData as String: Data(value.utf8)]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw PaperError("Couldn’t save the API key in Keychain (\(status)).")
    }
  }
}
