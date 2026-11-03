import XCTest
@testable import CopyTasteCore

final class CloudSyncTests: XCTestCase {
    private let phrase = "a long synthetic sync passphrase"
    private func entry(_ text: String, date: Date = Date()) -> ClipEntry {
        ClipEntry(kind: .text, text: text, sourceName: "Fixture", sourceBundleID: "org.example.editor", createdAt: date)
    }
    private func withURL(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-sync-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("history.copytaste"))
    }

    func testTwoClientsExchangeEncryptedClipsPinsAndCollections() throws {
        try withURL { url in
            let first = try CloudVault.connect(url: url, passphrase: phrase)
            let second = try CloudVault.connect(url: url, passphrase: phrase)
            let collection = ClipCollection(name: "Shared fixture")
            var note = entry("A synthetic note to sync")
            note.isPinned = true
            note.collectionID = collection.id
            let stateA = SyncState(snapshot: VaultSnapshot(entries: [note], collections: [collection]))
            _ = try first.exchange(stateA, preferences: Preferences())
            let stateB = SyncState(snapshot: VaultSnapshot(entries: [entry("A second synthetic note")]))
            let mergedB = try second.exchange(stateB, preferences: Preferences())
            let mergedA = try first.exchange(stateA, preferences: Preferences())
            XCTAssertEqual(mergedA, mergedB)
            XCTAssertEqual(mergedA.snapshot.entries.count, 2)
            XCTAssertTrue(mergedA.snapshot.entries.first { $0.id == note.id }?.isPinned == true)
            XCTAssertEqual(mergedA.snapshot.collections, [collection])
            XCTAssertNil(try Data(contentsOf: url).range(of: Data("A synthetic note to sync".utf8)))
        }
    }

    func testOfflinePeerCannotResurrectDeletedClip() {
        let original = entry("A deleted synthetic note", date: Date().addingTimeInterval(-20))
        let offline = SyncState(snapshot: VaultSnapshot(entries: [original]))
        var current = offline
        current.recordChanges(from: offline.snapshot, to: VaultSnapshot())
        XCTAssertTrue(current.merging(offline).snapshot.entries.isEmpty)
        XCTAssertTrue(offline.merging(current).snapshot.entries.isEmpty)
    }

    func testRecopyAfterDeletionIsAllowed() {
        let original = entry("A note copied again", date: Date().addingTimeInterval(-20))
        var current = SyncState(snapshot: VaultSnapshot(entries: [original]))
        current.recordChanges(from: current.snapshot, to: VaultSnapshot(), now: Date().addingTimeInterval(-10))
        let recopy = SyncState(snapshot: VaultSnapshot(entries: [entry("A note copied again")]))
        XCTAssertEqual(current.merging(recopy).snapshot.entries.count, 1)
    }

    func testClearBoundaryAndCollectionDeletionPropagate() {
        let collection = ClipCollection(name: "Delete fixture")
        var old = entry("Old synthetic note", date: Date().addingTimeInterval(-20))
        old.collectionID = collection.id
        let offline = SyncState(snapshot: VaultSnapshot(entries: [old], collections: [collection]))
        var current = SyncState()
        current.clearedAt = Date().addingTimeInterval(-10)
        current.deletedCollections[collection.id] = Date()
        let merged = current.merging(offline)
        XCTAssertTrue(merged.snapshot.entries.isEmpty)
        XCTAssertTrue(merged.snapshot.collections.isEmpty)
    }

    func testNewerPinChangeWinsDeterministically() {
        let old = entry("A pinned synthetic note", date: Date().addingTimeInterval(-20))
        var new = old
        new.isPinned = true
        new.modifiedAt = Date()
        let a = SyncState(snapshot: VaultSnapshot(entries: [old]))
        let b = SyncState(snapshot: VaultSnapshot(entries: [new]))
        XCTAssertEqual(a.merging(b), b.merging(a))
        XCTAssertTrue(a.merging(b).snapshot.entries[0].isPinned)
    }

    func testWrongPassphraseDoesNotModifyExistingVault() throws {
        try withURL { url in
            _ = try CloudVault.connect(url: url, passphrase: phrase)
            let original = try Data(contentsOf: url)
            XCTAssertThrowsError(try CloudVault.connect(url: url, passphrase: "a different synthetic passphrase"))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testUnchangedExchangeDoesNotRewriteOrTriggerSyncLoop() throws {
        try withURL { url in
            let vault = try CloudVault.connect(url: url, passphrase: phrase)
            let state = try vault.exchange(SyncState(), preferences: Preferences())
            let original = try Data(contentsOf: url)
            _ = try vault.exchange(state, preferences: Preferences())
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testWeakPassphraseCreatesNoFile() throws {
        try withURL { url in
            XCTAssertThrowsError(try CloudVault.connect(url: url, passphrase: "short"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testCollectionOverflowNeverWritesAnUnreadableVault() throws {
        try withURL { url in
            let vault = try CloudVault.connect(url: url, passphrase: phrase)
            let first = SyncState(snapshot: VaultSnapshot(collections: (0..<20).map { ClipCollection(name: "First \($0)") }))
            _ = try vault.exchange(first, preferences: Preferences())
            let bytes = try Data(contentsOf: url)
            let second = SyncState(snapshot: VaultSnapshot(collections: (0..<20).map { ClipCollection(name: "Second \($0)") }))
            XCTAssertThrowsError(try vault.exchange(second, preferences: Preferences()))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            let reopened = try CloudVault.connect(url: url, passphrase: phrase)
            XCTAssertEqual(try reopened.exchange(SyncState(), preferences: Preferences()).snapshot.collections.count, 20)
        }
    }

    func testIndependentlyInitialisedSaltsMergeWithTheSamePhrase() throws {
        try withURL { firstURL in
            try withURL { secondURL in
                let first = try CloudVault.connect(url: firstURL, passphrase: phrase)
                let second = try CloudVault.connect(url: secondURL, passphrase: phrase)
                let stateA = SyncState(snapshot: VaultSnapshot(entries: [entry("First offline fixture")]))
                let stateB = SyncState(snapshot: VaultSnapshot(entries: [entry("Second offline fixture")]))
                _ = try first.exchange(stateA, preferences: Preferences())
                _ = try second.exchange(stateB, preferences: Preferences())
                // Simulate delivery of a peer vault initialised independently with a different salt.
                try Data(contentsOf: secondURL).write(to: firstURL, options: .atomic)
                let combined = try first.exchange(stateA, preferences: Preferences())
                XCTAssertEqual(combined.snapshot.entries.count, 2)
                try Data(contentsOf: firstURL).write(to: secondURL, options: .atomic)
                XCTAssertEqual(try second.exchange(stateB, preferences: Preferences()), combined)
            }
        }
    }

    func testSyncFiltersSensitivePeerPayloadsBeforeWriting() throws {
        try withURL { url in
            let vault = try CloudVault.connect(url: url, passphrase: phrase)
            let state = SyncState(snapshot: VaultSnapshot(entries: [entry("password=synthetic-fixture")]))
            let result = try vault.exchange(state, preferences: Preferences())
            XCTAssertTrue(result.snapshot.entries.isEmpty)
            XCTAssertFalse(result.deletions.isEmpty)
        }
    }
}
