import Testing
import Foundation
@testable import FloatingChat

struct AppMetadataTests {
    @Test func bundleIsMenuBarOnly() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }

    @Test func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "tw.com.shitu.ocfloat")
    }
}

struct AppLanguageTests {
    @Test func storesOnlyInTheAppDomain() throws {
        let domain = "ocf-language-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        #expect(AppLanguage.current(defaults: defaults, domain: domain) == .system)
        AppLanguage.set(.traditionalChinese, defaults: defaults)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hant"])
        #expect(AppLanguage.current(defaults: defaults, domain: domain) == .traditionalChinese)
        AppLanguage.set(.english, defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, domain: domain) == .english)
        AppLanguage.set(.system, defaults: defaults)
        #expect(AppLanguage.current(defaults: defaults, domain: domain) == .system)
        defaults.removePersistentDomain(forName: domain)
    }
}
