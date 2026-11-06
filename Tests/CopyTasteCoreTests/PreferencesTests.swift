import XCTest
import CopyTasteCore

final class PreferencesTests: XCTestCase {
    func testLegacySettingsMigrateWithoutLosingEncryptedStorageOrExclusions() throws {
        let old = Data(#"{"captureEnabled":true,"captureImages":false,"storageMode":"encryptedFolder","customFolderPath":"/synthetic/folder","excludedBundleIDs":["org.example.private"],"persistPinnedOnly":true}"#.utf8)
        let settings = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(settings.schemaVersion, 2)
        XCTAssertTrue(settings.captureImages)
        XCTAssertTrue(settings.autoPaste)
        XCTAssertEqual(settings.storageMode, .encryptedFolder)
        XCTAssertEqual(settings.excludedBundleIDs, ["org.example.private"])
        XCTAssertTrue(settings.persistPinnedOnly)
        XCTAssertFalse(settings.clearHistoryOnSessionLock)
    }

    func testExplicitImageAndPasteOptOutsSurviveRelaunch() throws {
        var settings = Preferences()
        settings.captureImages = false
        settings.autoPaste = false
        settings.clearHistoryOnSessionLock = true
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(restored.captureImages)
        XCTAssertFalse(restored.autoPaste)
        XCTAssertTrue(restored.clearHistoryOnSessionLock)
    }

    func testUnknownLayoutPreservesStorageAndPrivacyPreferences() throws {
        let future = Data(#"{"schemaVersion":2,"selectorLayout":"future-layout","captureImages":false,"storageMode":"encryptedFolder","customFolderPath":"/synthetic/folder","excludedBundleIDs":["org.example.private"],"persistPinnedOnly":true}"#.utf8)
        let restored = try JSONDecoder().decode(Preferences.self, from: future)
        XCTAssertEqual(restored.selectorLayout, .pinnedAndRecent)
        XCTAssertEqual(restored.storageMode, .encryptedFolder)
        XCTAssertEqual(restored.customFolderPath, "/synthetic/folder")
        XCTAssertEqual(restored.excludedBundleIDs, ["org.example.private"])
        XCTAssertTrue(restored.persistPinnedOnly)
        XCTAssertFalse(restored.captureImages)
    }
}
