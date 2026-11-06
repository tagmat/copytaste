import AppKit
import CryptoKit
import CommonCrypto
import Foundation
import XCTest
@testable import CopyTaste
@testable import CopyTasteCore

final class PublicationReadinessTests: XCTestCase {
    private func note(_ text: String = "Synthetic note", at date: Date = Date()) -> ClipEntry {
        ClipEntry(kind: .text, text: text, sourceName: "Fixture", sourceBundleID: "org.example.editor", createdAt: date)
    }

    func testEnvironmentAndPuTTYFilesAreRejected() {
        for name in ["production.env", "staging.env", "app.env", ".env.local", "server.ppk"] {
            XCTAssertEqual(CapturePolicy().rejection(forFile: Data("ordinary-looking content".utf8), name: name), .secret)
        }
    }

    func testOrdinaryIdentifiersPathsEmailsVersionsAndYearsAreNotSecrets() {
        for text in ["/Users/Example/Docs/Report2.pdf", "John.Doe1@example.com", "iPhone15ProMax", "UIViewController2", "src/main/App.swift:42", "v1.2.3-beta.Release", "2026", "1234"] {
            XCTAssertNil(CapturePolicy().rejection(forText: text), text)
        }
        XCTAssertEqual(CapturePolicy().rejection(forText: "123456"), .secret)
        XCTAssertNil(CapturePolicy().rejection(forText: "123456", manual: true))
        XCTAssertEqual(CapturePolicy().rejection(forText: "password=fixture", manual: true), .secret)
    }

    func testWordsAreNotUnprefixedColors() {
        for word in ["facade", "accede", "decade", "deface", "abcdef"] { XCTAssertNil(HexColor(word)) }
        XCTAssertEqual(HexColor("#facade")?.hex, "#FACADE")
        XCTAssertEqual(HexColor("BDF27C")?.hex, "#BDF27C")
    }

    func testFingerprintCacheTracksContentAndSurvivesLegacyDecoding() throws {
        var entry = note()
        let original = entry.fingerprint
        entry.title = "Renamed"; entry.isPinned = true; entry.collectionID = UUID()
        XCTAssertEqual(entry.fingerprint, original)
        entry.text = "Revised fixture"
        XCTAssertNotEqual(entry.fingerprint, original)
        let encoded = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(ClipEntry.self, from: encoded).fingerprint, entry.fingerprint)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("contentFingerprint"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "modifiedAt")
        let restored = try JSONDecoder().decode(ClipEntry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.modifiedAt, restored.createdAt)
    }

    func testPreferenceRecoveryPreservesExclusionsAndStorageAndPausesCapture() throws {
        let data = Data(#"{"schemaVersion":2,"captureEnabled":true,"retentionDays":"broken","maximumEntries":300,"excludedBundleIDs":["org.example.private",42,"org.example.bank"],"storageMode":"encryptedFolder","customFolderPath":"/synthetic/folder"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(preferences.excludedBundleIDs, ["org.example.private", "org.example.bank"])
        XCTAssertEqual(preferences.storageMode, .encryptedFolder)
        XCTAssertFalse(preferences.captureEnabled)
        XCTAssertFalse(preferences.recoveryWarnings.isEmpty)
        XCTAssertEqual(preferences.retentionDays, 7)
        let unknown = try JSONDecoder().decode(Preferences.self, from: Data(#"{"captureEnabled":true,"storageMode":"future","excludedBundleIDs":["org.example.private"]}"#.utf8))
        XCTAssertFalse(unknown.captureEnabled)
        XCTAssertEqual(unknown.excludedBundleIDs, ["org.example.private"])
    }

    func testLegacyUpgradeDoesNotEnableFileCaptureWithoutOptIn() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"captureEnabled":true}"#.utf8))
        XCTAssertFalse(preferences.captureFiles)
    }

    func testPinOverflowCannotKeepSmallerUnpinnedEntries() {
        let now = Date()
        let sizes = [8, 8, 7, 2]
        let pins = sizes.enumerated().map { index, size in
            ClipEntry(kind: .file, fileData: Data(repeating: UInt8(index), count: size * 1_024 * 1_024), fileName: "fixture.bin", sourceName: "Fixture", sourceBundleID: "org.example.editor", createdAt: now.addingTimeInterval(-Double(index)), isPinned: true)
        }
        let small = note("small", at: now)
        var preferences = Preferences(); preferences.keepPinsPastExpiry = true
        let pruned = History.pruned(VaultSnapshot(entries: pins + [small]), preferences: preferences)
        XCTAssertEqual(pruned.entries.count, 3)
        XCTAssertTrue(pruned.entries.allSatisfy(\.isPinned))
        XCTAssertLessThanOrEqual(pruned.entries.reduce(0) { $0 + $1.byteCount }, History.maximumVaultBytes)
    }

    func testSameIdentityTimestampConflictsConverge() {
        let entry = note()
        var changed = entry; changed.isPinned = true; changed.title = "Renamed"
        let a = SyncState(snapshot: VaultSnapshot(entries: [entry]))
        let b = SyncState(snapshot: VaultSnapshot(entries: [changed]))
        XCTAssertEqual(a.merging(b), b.merging(a))
    }

    func testAutomaticPruningNeverAccumulatesDeletionEvidence() {
        var preferences = Preferences(); preferences.maximumEntries = 3
        var visible = VaultSnapshot()
        var shared = SyncState()
        let now = Date()
        for index in 0..<2_500 {
            let date = now.addingTimeInterval(Double(index) / 1_000)
            let next = History.inserting(note("Synthetic copy \(index)", at: date), into: visible, preferences: preferences, now: date)
            shared.applyLocalChanges(from: visible, to: next, now: date)
            visible = next
        }
        XCTAssertTrue(shared.deletions.isEmpty)
        XCTAssertTrue(shared.deletionLogWithinLimits)
        XCTAssertLessThanOrEqual(shared.snapshot.entries.count, 1_000)
    }

    func testClearCompactsOnlyDeletionEvidenceCoveredByItsBoundary() {
        let now = Date()
        var state = SyncState(snapshot: VaultSnapshot(entries: [note(at: now.addingTimeInterval(-100))]))
        state.deletions = ["older": now.addingTimeInterval(-10), "newer": now.addingTimeInterval(10)]
        state.applyLocalChanges(from: state.snapshot, to: VaultSnapshot(), clearAll: true, now: now)
        XCTAssertNil(state.deletions["older"])
        XCTAssertNotNil(state.deletions["newer"])
        XCTAssertTrue(state.snapshot.entries.isEmpty)
    }

    func testLocalExclusionsAndRetentionNeverDeleteSharedPeerHistory() throws {
        try withCloud { vault, _ in
            let old = note("Older fixture", at: Date().addingTimeInterval(-2 * 86_400))
            var preferences = Preferences(); preferences.retentionDays = 1
            preferences.excludedBundleIDs = [old.sourceBundleID]
            let result = try vault.exchange(SyncState(snapshot: VaultSnapshot(entries: [old])), preferences: preferences)
            XCTAssertEqual(result.snapshot.entries.map(\.id), [old.id])
            XCTAssertTrue(CloudVault.visibleSnapshot(result.snapshot, preferences: preferences).entries.isEmpty)
            XCTAssertTrue(result.deletions.isEmpty)
        }
    }

    func testCanonicalEquivalentPassphrasesOpenTheSameVault() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.copytaste")
        let phrase = "a long synthetiqué sync phrase"
        let vault = try CloudVault.connect(url: url, passphrase: phrase.decomposedStringWithCanonicalMapping)
        _ = try vault.exchange(SyncState(snapshot: VaultSnapshot(entries: [note()])), preferences: Preferences())
        let other = try CloudVault.connect(url: url, passphrase: phrase.precomposedStringWithCanonicalMapping)
        XCTAssertEqual(try other.readState().snapshot.entries.count, 1)
    }

    func testCompactionArchivesCiphertextAndRejectsStalePeers() throws {
        try withCloud { vault, url in
            let old = note("Deleted old pin", at: Date().addingTimeInterval(-100))
            let stale = try vault.exchange(SyncState(snapshot: VaultSnapshot(entries: [old])), preferences: Preferences())
            var deleted = stale
            deleted.recordChanges(from: stale.snapshot, to: VaultSnapshot())
            let state = try vault.exchange(deleted, preferences: Preferences())
            let fresh = try vault.compact(state)
            XCTAssertNotNil(fresh.generation)
            XCTAssertTrue(fresh.deletions.isEmpty)
            XCTAssertThrowsError(try vault.exchange(stale, preferences: Preferences()))
            XCTAssertTrue(try vault.exchange(fresh, preferences: Preferences()).snapshot.entries.isEmpty)
            let archives = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("before-compaction") }
            XCTAssertEqual(archives.count, 1)
            XCTAssertNil(try Data(contentsOf: archives[0]).range(of: Data("Deleted old pin".utf8)))
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testTokenizerKeepsSwiftDirectivesAndCSSColorsAndRecognizesPythonComments() {
        XCTAssertFalse(CodeTokenizer.tokens(in: "#if DEBUG\nlet value = #available(macOS 14, *)", fileName: "test.swift").contains { $0.kind == .comment })
        XCTAssertFalse(CodeTokenizer.tokens(in: "color: #fff;", fileName: "style.css").contains { $0.kind == .comment })
        XCTAssertTrue(CodeTokenizer.tokens(in: "# fixture\nvalue = 3", fileName: "test.py").contains { $0.kind == .comment })
    }

    @MainActor func testPickerFrameFitsShortScreens() {
        for available in [NSRect(x: 0, y: 0, width: 1024, height: 500), NSRect(x: -1000, y: 20, width: 800, height: 600)] {
            XCTAssertTrue(available.contains(PickerController.frame(in: available)))
        }
    }

    @MainActor func testMissingLocalVaultNeverCreatesAKeyOrFile() async throws {
        try await withModel(storage: .encryptedLocal) { model, _, url, _ in
            await model.unlock()
            XCTAssertTrue(model.isLocked)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @MainActor func testStorageAuthenticationPreservesNewerPrivacyChoices() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "net.tagmat.copytaste.review." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite)); defer { board.releaseGlobally() }
        var settings = Preferences(); settings.captureEnabled = true
        defaults.set(try JSONEncoder().encode(settings), forKey: "preferences.v1")
        var continuation: CheckedContinuation<Void, Never>?
        let key = SymmetricKey(size: .bits256)
        let model = AppModel(defaults: defaults, pasteboard: board, authenticateOwner: {
            await withCheckedContinuation { continuation = $0 }
        }, localLocation: { directory.appendingPathComponent("history.vault") }, loadKey: { _ in key }, workspaceNotifications: NotificationCenter(), screenNotifications: NotificationCenter())
        defer { model.shutdown() }
        let migration = Task { await model.applyStorage(.encryptedLocal, pinnedOnly: false) }
        for _ in 0..<1_000 { if continuation != nil { break }; await Task.yield() }
        guard let continuation else { XCTFail("Authentication never began"); migration.cancel(); return }
        model.toggleCapture(); model.setClearHistoryOnSessionLock(true)
        continuation.resume()
        await migration.value
        XCTAssertFalse(model.preferences.captureEnabled)
        XCTAssertTrue(model.preferences.clearHistoryOnSessionLock)
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.preferences.storageMode, .encryptedLocal)
        let saved = await model.flushStorage()
        XCTAssertTrue(saved)
    }

    @MainActor func testRecoverSessionRequiresAuthenticationAndAnActiveSession() async throws {
        try await withModel { model, _, _, screen in
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            XCTAssertTrue(model.isSessionSuspended)
            await model.unlock()
            XCTAssertNotNil(model.errorMessage)
            await model.recoverSession()
            XCTAssertFalse(model.isSessionSuspended)
            XCTAssertFalse(model.isLocked)
        }
    }

    @MainActor func testAppSwitchCountsThePendingCopyWithoutGuessingItsSource() async throws {
        let board = NSPasteboard(name: .init(UUID().uuidString)); defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, sourceProvider: { ClipboardSource(bundleID: "org.example.editor", name: "Fixture") }, secureInputProvider: { false })
        defer { monitor.stop() }
        var rejections: [RejectionReason] = []
        var captured = false
        monitor.onRejection = { rejections.append($0) }; monitor.onCapture = { _ in captured = true }
        board.clearContents(); board.setString("Synthetic before switching", forType: .string)
        monitor.sourceDidActivate("org.example.other")
        await monitor.poll()
        XCTAssertEqual(rejections, [.sourceChanged])
        XCTAssertFalse(captured)
    }

    @MainActor func testNativeFileWriterRetainsPrivateMarkersAndURLReading() async throws {
        try await withModel { model, board, _, _ in
            let entry = ClipEntry(kind: .file, fileData: Data("Synthetic file".utf8), fileName: "fixture.txt", sourceName: "Fixture", sourceBundleID: "org.example.editor")
            XCTAssertTrue(model.copy(entry))
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            let url = try XCTUnwrap(urls?.first)
            XCTAssertEqual(try Data(contentsOf: url), entry.fileData)
            XCTAssertTrue(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        }
    }

    func testLegacyDecomposedPassphraseVaultMigratesWithoutLosingData() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.copytaste")
        let phrase = "a long synthetiqué sync phrase"
        let salt = Data(repeating: 7, count: 16)
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let password = Array(phrase.decomposedStringWithCanonicalMapping.utf8)
        let status = password.withUnsafeBytes { password in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress!.assumingMemoryBound(to: CChar.self), password.count,
                    salt.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &keyBytes, keyBytes.count)
            }
        }
        XCTAssertEqual(status, Int32(kCCSuccess))
        var header = Data("CTSYNC01".utf8); header.append(salt)
        let state = SyncState(snapshot: VaultSnapshot(entries: [note("Legacy encrypted fixture")]))
        let box = try AES.GCM.seal(JSONEncoder().encode(state), using: SymmetricKey(data: keyBytes), authenticating: header)
        var file = header; file.append(try XCTUnwrap(box.combined)); try file.write(to: url)
        let vault = try CloudVault.connect(url: url, passphrase: phrase.precomposedStringWithCanonicalMapping)
        XCTAssertEqual(try vault.exchange(SyncState(), preferences: Preferences()).snapshot.entries.map(\.text), ["Legacy encrypted fixture"])
        XCTAssertTrue(try Data(contentsOf: url).starts(with: Data("CTSYNC02".utf8)))
    }

    @MainActor func testFullDeletionLogCanBeCompactedWithoutDisablingCapture() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.copytaste")
        let phrase = "a synthetic maintenance sync phrase"
        let vault = try CloudVault.connect(url: url, passphrase: phrase)
        let entry = note("Synthetic maintenance fixture")
        var state = SyncState(snapshot: VaultSnapshot(entries: [entry]))
        state.deletions = Dictionary(uniqueKeysWithValues: (0..<20_000).map { ("deleted-\($0)", Date()) })
        _ = try vault.exchange(state, preferences: Preferences())
        let suite = "net.tagmat.copytaste.maintenance." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        var settings = Preferences(); settings.storageMode = .iCloud; settings.captureEnabled = true
        defaults.set(try JSONEncoder().encode(settings), forKey: "preferences.v1")
        let board = NSPasteboard(name: .init(suite)); defer { board.releaseGlobally() }
        let model = AppModel(defaults: defaults, pasteboard: board, authenticateOwner: {}, cloudLocation: { url }, workspaceNotifications: NotificationCenter(), screenNotifications: NotificationCenter())
        defer { model.shutdown() }
        await model.unlock(syncPassphrase: phrase)
        XCTAssertFalse(model.isLocked)
        model.delete(entry)
        XCTAssertTrue(model.isCapturing)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.snapshot.entries.contains { $0.id == entry.id })
        await model.compactSyncHistory()
        model.delete(entry)
        let saved = await model.flushStorage()
        XCTAssertTrue(saved)
        XCTAssertFalse(model.snapshot.entries.contains { $0.id == entry.id })
        XCTAssertTrue(model.isCapturing)
    }

    @MainActor func testInactiveSessionCannotBeRecoveredByAuthenticationAlone() async throws {
        let suite = "net.tagmat.copytaste.inactive." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite)); defer { board.releaseGlobally() }
        let screen = NotificationCenter()
        var authenticated = false
        let model = AppModel(defaults: defaults, pasteboard: board, authenticateOwner: { authenticated = true }, sessionIsActive: { false }, workspaceNotifications: NotificationCenter(), screenNotifications: screen)
        defer { model.shutdown() }
        screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
        await model.recoverSession()
        XCTAssertTrue(authenticated)
        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.isSessionSuspended)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor func testMixedBitmapWinsOverFileURLAndUnsupportedCopiesAreCounted() async throws {
        let board = NSPasteboard(name: .init(UUID().uuidString)); defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board, sourceProvider: { ClipboardSource(bundleID: "org.example.editor", name: "Fixture") }, secureInputProvider: { false })
        defer { monitor.stop() }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        var entries: [ClipEntry] = []; var reasons: [RejectionReason] = []
        monitor.onCapture = { entries.append($0) }; monitor.onRejection = { reasons.append($0) }
        let image = NSPasteboardItem(); image.setData(data, forType: .png)
        image.setString("file:///nonexistent-synthetic-fixture.png", forType: .fileURL)
        board.clearContents(); XCTAssertTrue(board.writeObjects([image])); await monitor.poll()
        XCTAssertEqual(entries.first?.kind, .image)
        let unsupported = NSPasteboardItem(); unsupported.setData(Data("synthetic rtf".utf8), forType: .rtf)
        board.clearContents(); XCTAssertTrue(board.writeObjects([unsupported])); await monitor.poll()
        XCTAssertEqual(reasons, [.unsupported])
    }

    @MainActor private func withModel(storage: StorageMode = .memory,
        body: @MainActor (AppModel, NSPasteboard, URL, NotificationCenter) async throws -> Void) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "net.tagmat.copytaste.publication." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        var settings = Preferences(); settings.storageMode = storage
        defaults.set(try JSONEncoder().encode(settings), forKey: "preferences.v1")
        let board = NSPasteboard(name: .init(suite)); defer { board.releaseGlobally() }
        let screen = NotificationCenter()
        let url = directory.appendingPathComponent("history.vault")
        let key = SymmetricKey(size: .bits256)
        let model = AppModel(defaults: defaults, pasteboard: board, authenticateOwner: {}, localLocation: { url }, loadKey: { create in
            if create { XCTFail("Unexpected key creation") }
            return key
        }, sessionIsActive: { true }, workspaceNotifications: NotificationCenter(), screenNotifications: screen)
        defer { model.shutdown() }
        try await body(model, board, url, screen)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-publication-" + UUID().uuidString, isDirectory: true)
    }

    private func withCloud(_ body: (CloudVault, URL) throws -> Void) throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.copytaste")
        let vault = try CloudVault.connect(url: url, passphrase: "a synthetic publication sync phrase")
        try body(vault, url)
    }
}
