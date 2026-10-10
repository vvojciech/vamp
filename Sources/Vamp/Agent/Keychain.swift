import Foundation
import Security

/// Stores the optional Anthropic API key in the login keychain, never in preferences.
enum Keychain {
    private static let service = "com.vamp.anthropic-api-key"

    static var apiKey: String? {
        get {
            var item: CFTypeRef?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: service,
                                        kSecReturnData as String: true]
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = query
            add[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
