import Foundation
import Security

/// Which opencode server to talk to: the local background service (found automatically) or
/// a URL the user enters. The password goes to the Keychain, not to the defaults.
struct ServerSettings {
    private static let customKey = "serverUsesCustomURL"
    private static let urlKey = "serverURL"
    private static let keychainService = "tw.com.shitu.ocfloat.server"

    let defaults: UserDefaults

    var usesCustomServer: Bool {
        get { defaults.bool(forKey: Self.customKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.customKey) }
    }

    var urlString: String {
        get { defaults.string(forKey: Self.urlKey) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Self.urlKey) }
    }

    var password: String {
        get { Self.readPassword() ?? "" }
        nonmutating set { Self.writePassword(newValue) }
    }

    /// `nil` when the custom server is off or its URL is not usable.
    var customEndpoint: OpenCodeEndpoint? {
        guard usesCustomServer else { return nil }
        guard let url = Self.validURL(urlString) else { return nil }
        return OpenCodeEndpoint(baseURL: url, password: password)
    }

    static func validURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        return url
    }

    private static var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: OpenCodeEndpoint.username]
    }

    private static func readPassword() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData] = true
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writePassword(_ password: String) {
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var item = query
        item[kSecValueData] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
