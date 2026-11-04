import XCTest
import AppKit
@testable import CopyTaste
import CopyTasteCore

final class MonitorIntegrationTests: XCTestCase {
    @MainActor private func imageItem() throws -> NSPasteboardItem {
        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        image.bitmapData?.initialize(repeating: 128, count: image.bytesPerRow * image.pixelsHigh)
        let item = NSPasteboardItem()
        item.setData(try XCTUnwrap(image.representation(using: .png, properties: [:])), forType: .png)
        item.setString("https://example.org/synthetic-image.png", forType: .string)
        item.setString("https://example.org/synthetic-image.png", forType: .URL)
        return item
    }

    @MainActor func testBrowserImagePixelsWinOverAccompanyingURL() async throws {
        try withMonitor { monitor, board in
            var entries: [ClipEntry] = []
            monitor.onCapture = { entries.append($0) }
            board.clearContents()
            XCTAssertTrue(board.writeObjects([try imageItem()]))
            monitor.poll()
            XCTAssertEqual(entries.first?.kind, .image)
            XCTAssertNotNil(entries.first?.imageData)
            XCTAssertNil(entries.first?.text)
        }
    }

    @MainActor func testDisabledImageCaptureDoesNotSilentlySaveItsURL() async throws {
        try withMonitor { monitor, board in
            monitor.captureImages = false
            var captured = false
            monitor.onCapture = { _ in captured = true }
            board.clearContents()
            XCTAssertTrue(board.writeObjects([try imageItem()]))
            monitor.poll()
            XCTAssertFalse(captured)
        }
    }

    @MainActor func testPrivateImageAndURLAreBothRejected() async throws {
        try withMonitor { monitor, board in
            var captured = false
            monitor.onCapture = { _ in captured = true }
            let item = try imageItem()
            item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            board.clearContents()
            XCTAssertTrue(board.writeObjects([item]))
            monitor.poll()
            XCTAssertFalse(captured)
        }
    }

    @MainActor func testRegularFileCaptureStoresBytesAndName() async throws {
        try withMonitor { monitor, board in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-file-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("note.md")
            let bytes = Data("A harmless synthetic file".utf8)
            try bytes.write(to: url)
            var captured: ClipEntry?
            monitor.onCapture = { captured = $0 }
            let item = NSPasteboardItem(); item.setString(url.absoluteString, forType: .fileURL)
            board.clearContents(); XCTAssertTrue(board.writeObjects([item])); monitor.poll()
            XCTAssertEqual(captured?.kind, .file)
            XCTAssertEqual(captured?.fileData, bytes)
            XCTAssertEqual(captured?.fileName, "note.md")
        }
    }

    @MainActor func testFileSymlinkCannotBypassProtectedNameFilter() async throws {
        try withMonitor { monitor, board in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-file-test-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let original = folder.appendingPathComponent("private.key")
            try Data("synthetic fixture".utf8).write(to: original)
            let link = folder.appendingPathComponent("ordinary.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
            var captured = false; monitor.onCapture = { _ in captured = true }
            let item = NSPasteboardItem(); item.setString(link.absoluteString, forType: .fileURL)
            board.clearContents(); XCTAssertTrue(board.writeObjects([item])); monitor.poll()
            XCTAssertFalse(captured)
        }
    }
    @MainActor private func withMonitor(source: String? = "org.example.editor", secure: Bool = false,
        body: (ClipboardMonitor, NSPasteboard) throws -> Void) throws {
        let board = NSPasteboard(name: .init("net.tagmat.copytaste.test." + UUID().uuidString))
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board,
            sourceProvider: { ClipboardSource(bundleID: source, name: "Synthetic editor") },
            secureInputProvider: { secure })
        try body(monitor, board)
        monitor.stop()
    }

    @MainActor func testMonitorCapturesHarmlessCopyExactlyOnce() async throws {
        try withMonitor { monitor, board in
            var captured: [ClipEntry] = []
            monitor.onCapture = { captured.append($0) }
            board.clearContents()
            XCTAssertTrue(board.setString("A harmless synthetic note", forType: .string))
            monitor.poll()
            monitor.poll()
            XCTAssertEqual(captured.count, 1)
            XCTAssertEqual(captured.first?.text, "A harmless synthetic note")
        }
    }

    @MainActor func testCapturesBareHexColorWithoutCapturingNumericVerificationCode() async throws {
        try withMonitor { monitor, board in
            var captured: [ClipEntry] = []
            var rejected: [RejectionReason] = []
            monitor.onCapture = { captured.append($0) }
            monitor.onRejection = { rejected.append($0) }
            for value in ["bDf27c", "123456"] {
                board.clearContents()
                XCTAssertTrue(board.setString(value, forType: .string))
                monitor.poll()
            }
            XCTAssertEqual(captured.map(\.text), ["bDf27c"])
            XCTAssertTrue(captured.first.map(PickerFilter.colors.includes) == true)
            XCTAssertEqual(History.search(captured, query: "#BDF27C").first?.text, "bDf27c")
            XCTAssertEqual(rejected, [.secret])
        }
    }

    @MainActor func testMonitorRejectsMarkedPayloadAndSecrets() async throws {
        try withMonitor { monitor, board in
            var captured: [ClipEntry] = []
            var reasons: [RejectionReason] = []
            monitor.onCapture = { captured.append($0) }
            monitor.onRejection = { reasons.append($0) }
            let marked = NSPasteboardItem()
            marked.setString("Synthetic private note", forType: .string)
            marked.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            board.clearContents()
            XCTAssertTrue(board.writeObjects([marked]))
            monitor.poll()
            board.clearContents()
            XCTAssertTrue(board.setString("password=synthetic-fixture", forType: .string))
            monitor.poll()
            XCTAssertTrue(captured.isEmpty)
            XCTAssertEqual(reasons, [.concealed, .secret])
        }
    }

    @MainActor func testMonitorRejectsProtectedSourceEvenWithoutPrivateMarker() async throws {
        try withMonitor(source: "com.apple.Passwords") { monitor, board in
            var captured = false
            var reason: RejectionReason?
            monitor.onCapture = { _ in captured = true }
            monitor.onRejection = { reason = $0 }
            board.clearContents()
            XCTAssertTrue(board.setString("Unmarked synthetic fixture", forType: .string))
            monitor.poll()
            XCTAssertFalse(captured)
            XCTAssertEqual(reason, .excludedApplication)
        }
    }

    @MainActor func testMonitorDoesNotImportClipboardOnStartOrResume() async throws {
        try withMonitor { monitor, board in
            var captured = false
            monitor.onCapture = { _ in captured = true }
            board.clearContents()
            XCTAssertTrue(board.setString("Existing synthetic clipboard", forType: .string))
            monitor.start()
            monitor.poll()
            monitor.stop()
            XCTAssertFalse(captured)
        }
    }

    @MainActor func testMemorySessionLockDoesNotCreatePersistencePreferences() async throws {
        let suite = "net.tagmat.copytaste.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let model = AppModel(defaults: defaults, pasteboard: board)
        XCTAssertEqual(model.preferences.storageMode, .memory)
        XCTAssertFalse(model.isLocked)
        model.lock()
        XCTAssertTrue(model.isLocked)
        await model.unlock()
        XCTAssertFalse(model.isLocked)
        XCTAssertTrue(model.snapshot.entries.isEmpty)
        XCTAssertNil(defaults.data(forKey: "preferences.v1"))
        model.shutdown()
    }
}
