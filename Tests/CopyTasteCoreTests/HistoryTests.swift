import XCTest
@testable import CopyTasteCore

final class HistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func entry(_ text: String, daysAgo: Double = 0, pinned: Bool = false) -> ClipEntry {
        ClipEntry(kind: .text, text: text, sourceName: "Fixture", sourceBundleID: "org.example.fixture",
                  createdAt: now.addingTimeInterval(-daysAgo * 86_400), isPinned: pinned)
    }

    func testDuplicatesArePromotedAndKeepPinCollectionAndIdentity() {
        let collection = ClipCollection(name: "Notes")
        var original = entry("A repeated note", daysAgo: 1, pinned: true)
        original.collectionID = collection.id
        let state = VaultSnapshot(entries: [original], collections: [collection])
        let result = History.inserting(entry("A repeated note"), into: state, preferences: Preferences(), now: now)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].id, original.id)
        XCTAssertTrue(result.entries[0].isPinned)
        XCTAssertEqual(result.entries[0].collectionID, collection.id)
        XCTAssertEqual(result.entries[0].createdAt, now)
    }

    func testPinsExpireWithOrdinaryEntries() {
        let state = VaultSnapshot(entries: [entry("old pinned", daysAgo: 8, pinned: true), entry("old", daysAgo: 8), entry("recent", daysAgo: 1)])
        let result = History.pruned(state, preferences: Preferences(), now: now)
        XCTAssertEqual(result.entries.map(\.text), ["recent"])
    }

    func testCountLimitIsHardEvenForPins() {
        var preferences = Preferences()
        preferences.maximumEntries = 2
        let state = VaultSnapshot(entries: [entry("first", daysAgo: 2, pinned: true), entry("second", daysAgo: 1), entry("third")])
        XCTAssertEqual(History.pruned(state, preferences: preferences, now: now).entries.map(\.text), ["third", "second"])
    }

    func testByteBudgetIsBounded() {
        let entries = (0..<8).map { n in ClipEntry(kind: .image, imageData: Data(repeating: UInt8(n), count: 4 * 1_024 * 1_024), sourceName: "Fixture", sourceBundleID: "org.example.fixture", createdAt: now) }
        let result = History.pruned(VaultSnapshot(entries: entries), preferences: Preferences(), now: now)
        XCTAssertLessThanOrEqual(result.entries.reduce(0) { $0 + $1.byteCount }, History.maximumVaultBytes)
        XCTAssertEqual(result.entries.count, 6)
    }

    func testSearchMatchesAllWordsAcrossMetadataAndText() {
        let entries = [entry("A café in Istanbul"), entry("A note about Ankara")]
        XCTAssertEqual(History.search(entries, query: "CAFE fixture").count, 1)
        XCTAssertEqual(History.search(entries, query: "  \n ").count, 2)
        XCTAssertTrue(History.search(entries, query: "café missing").isEmpty)
    }

    func testImageAndTextHaveDifferentFingerprints() {
        let text = entry("abc")
        let image = ClipEntry(kind: .image, imageData: Data("abc".utf8), sourceName: "Fixture", sourceBundleID: "org.example.fixture")
        XCTAssertNotEqual(text.fingerprint, image.fingerprint)
    }
}
