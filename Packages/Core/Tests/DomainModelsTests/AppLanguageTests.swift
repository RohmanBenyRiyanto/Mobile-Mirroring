import XCTest
@testable import DomainModels

final class AppLanguageTests: XCTestCase {
    private var suite = ""
    private func defaults() -> UserDefaults {
        let name = "benz-language-test-\(UUID().uuidString)"
        suite = name
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testAChoiceIsSavedWithEnglishAsTheFallback() {
        let store = defaults()
        AppLanguage.choose(AppLanguage("id"), in: store)
        XCTAssertEqual(AppLanguage.chosen(in: store)?.code, "id")
        XCTAssertEqual(store.array(forKey: "AppleLanguages") as? [String], ["id", "en"])
        AppLanguage.choose(AppLanguage("en"), in: store)
        XCTAssertEqual(store.array(forKey: "AppleLanguages") as? [String], ["en"])
    }

    func testFollowingTheSystemRemovesTheOverride() {
        let store = defaults()
        AppLanguage.choose(AppLanguage("id"), in: store)
        AppLanguage.choose(nil, in: store)
        XCTAssertNil(AppLanguage.chosen(in: store))
        XCTAssertNil(store.persistentDomain(forName: suite)?["AppleLanguages"], "the app's own override is gone")
    }

    func testAnUnknownSavedLanguageIsIgnored() {
        let store = defaults()
        store.set("xx", forKey: AppLanguage.overrideKey)
        XCTAssertNil(AppLanguage.chosen(in: store))
    }

    func testNamesAreShownInTheLanguageItself() {
        XCTAssertEqual(AppLanguage("id").nativeName, "Bahasa Indonesia")
        XCTAssertEqual(AppLanguage("en").nativeName, "English")
    }

    func testRestartIsNeededOnlyWhenTheChoiceChanged() {
        XCTAssertFalse(AppLanguage.needsRestart(started: nil, now: nil))
        XCTAssertTrue(AppLanguage.needsRestart(started: nil, now: AppLanguage("id")))
        XCTAssertFalse(AppLanguage.needsRestart(started: AppLanguage("id"), now: AppLanguage("id")))
    }
}
