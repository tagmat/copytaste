import XCTest
import AppKit
@testable import CopyTaste
import CopyTasteCore

final class AppIntegrationTests: XCTestCase {
    @MainActor func testSuccessfulCloudReopenResumesPeriodicMergeAfterFailure() async throws {
        let suite = "net.tagmat.copytaste.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.copytaste")
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        var preferences = Preferences()
        preferences.storageMode = .iCloud
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences.v1")
        let phrase = "a synthetic cloud recovery phrase"
        let model = AppModel(defaults: defaults, pasteboard: board, authenticateOwner: {}, cloudLocation: { url })
        await model.unlock(syncPassphrase: phrase)
        XCTAssertFalse(model.isLocked)
        let valid = try Data(contentsOf: url)
        try Data("damaged synthetic fixture".utf8).write(to: url)
        model.syncNow(userInitiated: true)
        XCTAssertNotNil(model.errorMessage)
        try valid.write(to: url)
        model.lock()
        await model.unlock(syncPassphrase: phrase)
        XCTAssertFalse(model.isLocked)
        let peer = try CloudVault.connect(url: url, passphrase: phrase)
        let clip = ClipEntry(kind: .text, text: "A synthetic recovery note", sourceName: "Fixture", sourceBundleID: "org.example.editor")
        _ = try peer.exchange(SyncState(snapshot: VaultSnapshot(entries: [clip])), preferences: preferences)
        model.syncNow() // The regular timer path must no longer be suspended.
        XCTAssertTrue(model.snapshot.entries.contains { $0.id == clip.id })
        model.shutdown()
    }
    @MainActor func testDemoDoesNotWriteSettingsAndUsesIsolatedPasteboard() async throws {
        let suite = "net.tagmat.copytaste.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let model = AppModel(demo: true, defaults: defaults, pasteboard: board)
        let entry = try XCTUnwrap(model.snapshot.entries.first)
        model.copy(entry)
        XCTAssertEqual(board.string(forType: .string), entry.text)
        XCTAssertTrue(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        XCTAssertNil(defaults.data(forKey: "preferences.v1"))
        XCTAssertFalse(model.isCapturing)
        model.shutdown()
    }

    @MainActor func testClipboardClearDoesNotOverwriteANewerCopy() async throws {
        let board = NSPasteboard(name: .init("net.tagmat.copytaste.test." + UUID().uuidString))
        defer { board.releaseGlobally() }
        let model = AppModel(demo: true, pasteboard: board)
        model.copy(try XCTUnwrap(model.snapshot.entries.first))
        board.clearContents()
        board.setString("Newer synthetic copy", forType: .string)
        model.clearHistory()
        XCTAssertEqual(board.string(forType: .string), "Newer synthetic copy")
        model.shutdown()
    }

    @MainActor func testCopyOwnedClipboardIsClearedOnShutdown() async throws {
        let board = NSPasteboard(name: .init("net.tagmat.copytaste.test." + UUID().uuidString))
        defer { board.releaseGlobally() }
        let model = AppModel(demo: true, pasteboard: board)
        model.copy(try XCTUnwrap(model.snapshot.entries.first))
        model.shutdown()
        XCTAssertNil(board.string(forType: .string))
        XCTAssertTrue(model.snapshot.entries.isEmpty)
    }

    @MainActor func testCollectionLifecycleAndSearch() async throws {
        let model = AppModel(demo: true)
        let entry = try XCTUnwrap(model.snapshot.entries.first)
        model.createCollection("Research")
        let collection = try XCTUnwrap(model.snapshot.collections.first { $0.name == "Research" })
        model.move(entry, to: collection.id)
        XCTAssertEqual(model.visibleEntries.count, 1)
        model.query = "good ideas"
        XCTAssertEqual(model.visibleEntries.first?.id, entry.id)
        model.deleteCollection(collection.id)
        XCTAssertNil(model.snapshot.entries.first { $0.id == entry.id }?.collectionID)
        XCTAssertNotNil(model.snapshot.entries.first { $0.id == entry.id })
        model.shutdown()
    }

    @MainActor func testPinAndDeletionActuallyUpdateHistory() async throws {
        let model = AppModel(demo: true)
        let entry = try XCTUnwrap(model.snapshot.entries.first)
        let original = entry.isPinned
        model.togglePin(entry)
        XCTAssertEqual(model.snapshot.entries.first { $0.id == entry.id }?.isPinned, !original)
        model.delete(entry)
        XCTAssertFalse(model.snapshot.entries.contains { $0.id == entry.id })
        model.clearHistory()
        XCTAssertTrue(model.snapshot.entries.isEmpty)
        model.shutdown()
    }
}
