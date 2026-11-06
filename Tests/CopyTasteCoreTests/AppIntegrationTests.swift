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
        _ = try CloudVault.connect(url: url, passphrase: phrase)
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

    @MainActor func testMissingCloudFileKeepsEditsAndDeletesPendingUntilRetry() async throws {
        let suite = "net.tagmat.copytaste.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.copytaste")
        let offline = directory.appendingPathComponent("offline.copytaste")
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        var preferences = Preferences()
        preferences.storageMode = .iCloud
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences.v1")
        let phrase = "a synthetic recovery test phrase"
        let vault = try CloudVault.connect(url: url, passphrase: phrase)
        let old = ClipEntry(kind: .text, text: "Old synthetic clip", sourceName: "Fixture", sourceBundleID: "org.example.editor")
        let stale = SyncState(snapshot: VaultSnapshot(entries: [old]))
        _ = try vault.exchange(stale, preferences: preferences)
        let screen = NotificationCenter()
        let model = AppModel(defaults: defaults, pasteboard: board, authenticateOwner: {}, cloudLocation: { url },
            workspaceNotifications: NotificationCenter(), screenNotifications: screen)
        defer { model.shutdown() }
        await model.unlock(syncPassphrase: phrase)
        XCTAssertFalse(model.isLocked)

        try FileManager.default.moveItem(at: url, to: offline)
        XCTAssertNil(model.saveClip(id: old.id, title: "Edited", text: "New synthetic clip"))
        XCTAssertEqual(model.snapshot.entries.map(\.text), ["New synthetic clip"])
        XCTAssertTrue(model.hasPendingSync)
        XCTAssertNotNil(model.syncIssue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.hasPendingSync)
        screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        XCTAssertFalse(model.isLocked)
        XCTAssertEqual(model.snapshot.entries.map(\.text), ["New synthetic clip"])
        XCTAssertTrue(model.hasPendingSync)

        try FileManager.default.moveItem(at: offline, to: url)
        model.syncNow(userInitiated: true)
        XCTAssertFalse(model.hasPendingSync)
        XCTAssertNil(model.syncIssue)
        let result = try vault.exchange(stale, preferences: preferences)
        XCTAssertEqual(result.snapshot.entries.map(\.text), ["New synthetic clip"])
    }

    @MainActor func testEditingKeepsPinAndCollectionAndRejectsSecrets() async throws {
        let model = AppModel(demo: true)
        defer { model.shutdown() }
        let old = try XCTUnwrap(model.snapshot.entries.first)
        XCTAssertNotNil(model.saveClip(id: old.id, title: "", text: "password=synthetic"))
        XCTAssertTrue(model.snapshot.entries.contains(where: { $0.id == old.id }))
        XCTAssertNil(model.saveClip(id: old.id, title: "Fresh label", text: "Revised sample note"))
        let edited = try XCTUnwrap(model.selectedEntry)
        XCTAssertEqual(edited.title, "Fresh label")
        XCTAssertEqual(edited.isPinned, old.isPinned)
        XCTAssertEqual(edited.collectionID, old.collectionID)
        XCTAssertFalse(model.snapshot.entries.contains(where: { $0.id == old.id }))
        XCTAssertNil(model.saveClip(id: nil, title: "A new snippet", text: "Synthetic workflow sample"))
        XCTAssertEqual(model.selectedEntry?.text, "Synthetic workflow sample")
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
        try model.saveFolder(name: "Research")
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

    @MainActor func testFolderCreationRenameAndRemovalKeepTheClipAndRejectStaleMoves() async throws {
        let model = AppModel(demo: true)
        defer { model.shutdown() }
        let original = try XCTUnwrap(model.snapshot.entries.first { $0.collectionID == nil })
        XCTAssertThrowsError(try model.saveFolder(name: "Missing clip", moving: UUID()))
        XCTAssertFalse(model.snapshot.collections.contains { $0.name == "Missing clip" })
        let id = try model.saveFolder(name: "References", moving: original.id)
        XCTAssertThrowsError(try model.saveFolder(name: "references"))
        try model.saveFolder(name: "Reference shelf", id: id)
        XCTAssertEqual(model.snapshot.collections.first(where: { $0.id == id })?.name, "Reference shelf")
        let filed = try XCTUnwrap(model.snapshot.entries.first { $0.id == original.id })
        XCTAssertTrue(FolderScope.folder(id).includes(filed))
        XCTAssertFalse(FolderScope.unfiled.includes(filed))
        XCTAssertTrue(model.deleteCollection(id))
        model.move(filed, to: id)
        let unfiled = try XCTUnwrap(model.snapshot.entries.first { $0.id == original.id })
        XCTAssertTrue(FolderScope.unfiled.includes(unfiled))
        XCTAssertEqual(unfiled.fingerprint, original.fingerprint)
    }
}
