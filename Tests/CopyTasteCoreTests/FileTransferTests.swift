import XCTest
import AppKit
@testable import CopyTaste
import CopyTasteCore

final class FileTransferTests: XCTestCase {
    @MainActor func testTransferCreatesPrivateFileAndCleansItUp() async throws {
        let store = TransferFileStore()
        let bytes = Data("A synthetic attachment".utf8)
        let entry = ClipEntry(kind: .file, fileData: bytes, fileName: "notes.txt", sourceName: "Fixture", sourceBundleID: "org.example.fixture")
        let url = try store.materialize(entry)
        defer { store.removeAll() }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(url.lastPathComponent, "notes.txt")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testFileCopyWritesAFileURLAndShutdownRemovesTransfer() async throws {
        let board = NSPasteboard(name: .init("net.tagmat.copytaste.test." + UUID().uuidString))
        defer { board.releaseGlobally() }
        let model = AppModel(demo: true, pasteboard: board)
        let entry = ClipEntry(kind: .file, fileData: Data("Synthetic attachment".utf8), fileName: "note.md", sourceName: "Fixture", sourceBundleID: "org.example.fixture")
        XCTAssertTrue(model.copy(entry))
        let url = try XCTUnwrap(URL(string: XCTUnwrap(board.string(forType: .fileURL))))
        XCTAssertTrue(url.isFileURL)
        XCTAssertNil(board.string(forType: .string))
        XCTAssertTrue(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        model.shutdown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSensitiveFilesAndTextCredentialsAreRejected() {
        let policy = CapturePolicy()
        for name in ["login.key", ".env", "passwords.csv", "vault.kdbx", "id_ed25519", "secrets.json"] {
            XCTAssertEqual(policy.rejection(forFile: Data("synthetic".utf8), name: name), .secret)
        }
        XCTAssertEqual(policy.rejection(forFile: Data("password=synthetic-fixture".utf8), name: "config.txt"), .secret)
        XCTAssertNil(policy.rejection(forFile: Data("A harmless note".utf8), name: "note.md"))
    }

    @MainActor func testPDFPreviewRendersInMemory() async throws {
        let data = try XCTUnwrap(DemoContent.samplePDF())
        let entry = ClipEntry(kind: .file, fileData: data, fileName: "sample.pdf", sourceName: "Fixture", sourceBundleID: "org.example.fixture")
        XCTAssertNotNil(PreviewCache.shared.thumbnail(entry))
        PreviewCache.shared.removeAll()
    }

    @MainActor func testClearHistoryAlsoRemovesOutgoingTransfer() async throws {
        let board = NSPasteboard(name: .init("net.tagmat.copytaste.test." + UUID().uuidString))
        defer { board.releaseGlobally() }
        let model = AppModel(demo: true, pasteboard: board)
        defer { model.shutdown() }
        let entry = ClipEntry(kind: .file, fileData: Data("Synthetic file".utf8), fileName: "note.txt", sourceName: "Fixture", sourceBundleID: "org.example.fixture")
        XCTAssertTrue(model.copy(entry))
        let url = try XCTUnwrap(URL(string: XCTUnwrap(board.string(forType: .fileURL))))
        model.clearHistory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(board.string(forType: .fileURL))
    }

    func testFileNamesAreSearchable() {
        let entry = ClipEntry(kind: .file, fileData: Data(), fileName: "Project notes.pdf", sourceName: "Finder", sourceBundleID: "com.apple.finder")
        XCTAssertEqual(History.search([entry], query: "project PDF").first?.id, entry.id)
        XCTAssertTrue(History.search([entry], query: "missing.zip").isEmpty)
    }

    func testCarouselHasUniqueCardsOnBothSidesOfTheSelection() {
        let slots = PickerLayout.slots(count: 9, selection: 0)
        XCTAssertEqual(slots.map(\.offset), [-3, -2, -1, 0, 1, 2, 3])
        XCTAssertEqual(Set(slots.map(\.index)).count, 7)
        XCTAssertEqual(slots.first { $0.offset == 0 }?.index, 0)
        XCTAssertTrue(PickerLayout.slots(count: 0, selection: 0).isEmpty)
        XCTAssertEqual(PickerLayout.slots(count: 2, selection: 1).count, 2)
    }

    func testManyPinsDoNotHideNewRecentClips() {
        let now = Date()
        let pins = (0..<100).map { offset in
            ClipEntry(kind: .text, text: "Pinned sample", sourceName: "Fixture", sourceBundleID: "org.example.fixture", createdAt: now.addingTimeInterval(-Double(offset + 1)), isPinned: true)
        }
        let latest = ClipEntry(kind: .text, text: "New sample", sourceName: "Fixture", sourceBundleID: "org.example.fixture", createdAt: now)
        let split = PickerLayout.ordered(pins + [latest], layout: .pinnedAndRecent)
        XCTAssertEqual(split.count, 101)
        XCTAssertEqual(split.filter { !$0.isPinned }.first?.id, latest.id)
        XCTAssertTrue(split.prefix(100).allSatisfy(\.isPinned))
        XCTAssertEqual(PickerLayout.ordered(pins + [latest], layout: .orbit).first?.id, latest.id)
    }
}
