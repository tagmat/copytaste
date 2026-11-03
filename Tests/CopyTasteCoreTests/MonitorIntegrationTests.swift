import XCTest
import AppKit
@testable import CopyTaste
import CopyTasteCore

final class MonitorIntegrationTests: XCTestCase {
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
