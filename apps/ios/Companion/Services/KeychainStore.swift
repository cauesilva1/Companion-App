import Foundation
import Security

enum KeychainStore {
  private static let service = "com.companion.tamagotchi.keys"

  enum Key: String {
    case nvidia = "NVIDIA_API_KEY"
    case openrouter = "OPENROUTER_API_KEY"
    case authToken = "AUTH_TOKEN"
    case authEmail = "AUTH_EMAIL"
    case spotifyAccess = "SPOTIFY_ACCESS"
    case spotifyRefresh = "SPOTIFY_REFRESH"
    case spotifyExpires = "SPOTIFY_EXPIRES"
  }

  static func get(_ key: Key) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    let value = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (value?.isEmpty == false) ? value : nil
  }

  static func set(_ key: Key, value: String?) {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    delete(key)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    SecItemAdd(query as CFDictionary, nil)
  }

  static func delete(_ key: Key) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
    ]
    SecItemDelete(query as CFDictionary)
  }

  static var hasAnyLLMKey: Bool {
    Self.get(.nvidia) != nil || Self.get(.openrouter) != nil
  }

  static var authToken: String? { Self.get(.authToken) }
  static var authEmail: String? { Self.get(.authEmail) }
  static var isLoggedIn: Bool { authToken != nil }

  static func saveSession(token: String, email: String) {
    set(.authToken, value: token)
    set(.authEmail, value: email.lowercased())
  }

  static func clearSession() {
    delete(.authToken)
    delete(.authEmail)
  }
}
