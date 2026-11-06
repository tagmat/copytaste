import AppKit
import CopyTasteCore
import XCTest
@testable import CopyTaste

final class SessionLifecycleTests: XCTestCase {
    @MainActor func testScreenUnlockRetainsHistoryAndCapturesOnlyNewCopies() async throws {
        try await withSession { model, monitor, board, _, screen in
            copy("Before the synthetic screen lock", to: board, monitor: monitor)
            let before = model.snapshot
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            XCTAssertTrue(model.isLocked)
            XCTAssertTrue(model.isSessionSuspended)
            XCTAssertFalse(model.isCapturing)
            XCTAssertEqual(model.snapshot, before)

            board.clearContents()
            board.setString("Copied while the session was suspended", forType: .string)
            await model.unlock()
            XCTAssertTrue(model.isLocked)
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            XCTAssertFalse(model.isLocked)
            XCTAssertFalse(model.isSessionSuspended)
            XCTAssertTrue(model.isCapturing)
            monitor.poll()
            XCTAssertEqual(model.snapshot.entries.map(\.text), before.entries.map(\.text))
            copy("After the synthetic screen unlock", to: board, monitor: monitor)
            XCTAssertEqual(model.snapshot.entries.first?.text, "After the synthetic screen unlock")
            XCTAssertEqual(model.snapshot.entries.count, 2)
        }
    }

    @MainActor func testWakeWaitsForEverySuspensionReasonAndHandlesDuplicateNotifications() async throws {
        try await withSession { model, _, _, workspace, screen in
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            XCTAssertTrue(model.isLocked)
            XCTAssertFalse(model.isCapturing)
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            XCTAssertFalse(model.isLocked)
            XCTAssertTrue(model.isCapturing)

            for (pause, resume) in [
                (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
                (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
                (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification)
            ] {
                workspace.post(name: pause, object: nil)
                XCTAssertFalse(model.isCapturing)
                workspace.post(name: resume, object: nil)
                XCTAssertTrue(model.isCapturing)
            }
        }
    }

    @MainActor func testManualPauseAndManualLockArePreservedAcrossScreenUnlock() async throws {
        try await withSession { model, _, _, _, screen in
            model.toggleCapture()
            XCTAssertFalse(model.preferences.captureEnabled)
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            XCTAssertFalse(model.isCapturing)
            XCTAssertFalse(model.preferences.captureEnabled)

            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            model.lock()
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            XCTAssertTrue(model.isLocked)
            await model.unlock()
            XCTAssertFalse(model.isLocked)
            XCTAssertFalse(model.isCapturing)
        }
    }

    @MainActor func testOptionalClearingRestartsMemoryCaptureAfterUnlock() async throws {
        var settings = Preferences()
        settings.clearHistoryOnSessionLock = true
        try await withSession(settings: settings) { model, monitor, board, workspace, screen in
            copy("Synthetic clip cleared by policy", to: board, monitor: monitor)
            XCTAssertEqual(model.snapshot.entries.count, 1)
            workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            XCTAssertTrue(model.snapshot.entries.isEmpty)
            workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            XCTAssertTrue(model.isLocked)
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            XCTAssertTrue(model.isCapturing)
            copy("Synthetic clip captured after clearing", to: board, monitor: monitor)
            XCTAssertEqual(model.snapshot.entries.first?.text, "Synthetic clip captured after clearing")
        }
    }

    @MainActor func testScreenUnlockDoesNotOpenAnInitiallyLockedVault() async throws {
        var settings = Preferences()
        settings.storageMode = .encryptedLocal
        try await withSession(settings: settings) { model, _, _, _, screen in
            XCTAssertTrue(model.isLocked)
            screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
            screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
            XCTAssertTrue(model.isLocked)
            XCTAssertFalse(model.isCapturing)
        }
    }

    @MainActor func testLockAndUnlockDuringActivationCancelsTheOldPaste() async throws {
        try await withSession { model, _, _, _, screen in
            let session = model.sessionEpoch
            var sent = false
            let service = PasteService(trusted: { true }, secureInput: { false }, frontmostPID: { 42 },
                activate: { _ in true }, send: { _ in sent = true }, settle: {
                    screen.post(name: .init("com.apple.screenIsLocked"), object: nil)
                    screen.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
                })
            let result = await service.perform(copy: { true },
                destination: PasteDestination(processID: 42, name: "Fixture"), automatic: true, demo: false,
                stillValid: { !model.isLocked && model.sessionEpoch == session })
            XCTAssertFalse(model.isLocked)
            XCTAssertEqual(result, .destinationChanged)
            XCTAssertFalse(sent)
        }
    }

    @MainActor private func copy(_ value: String, to board: NSPasteboard, monitor: ClipboardMonitor) {
        board.clearContents()
        XCTAssertTrue(board.setString(value, forType: .string))
        monitor.poll()
    }

    @MainActor private func withSession(settings: Preferences = Preferences(),
        body: @MainActor (AppModel, ClipboardMonitor, NSPasteboard, NotificationCenter, NotificationCenter) async throws -> Void) async throws {
        let suite = "net.tagmat.copytaste.session-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = settings
        settings.captureEnabled = true
        defaults.set(try JSONEncoder().encode(settings), forKey: "preferences.v1")
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let workspace = NotificationCenter()
        let screen = NotificationCenter()
        let monitor = ClipboardMonitor(pasteboard: board,
            sourceProvider: { ClipboardSource(bundleID: "org.example.editor", name: "Synthetic editor") },
            secureInputProvider: { false })
        let model = AppModel(defaults: defaults, pasteboard: board,
            authenticateOwner: { XCTFail("Unexpected authentication in session tests") },
            workspaceNotifications: workspace, screenNotifications: screen, makeMonitor: { _ in monitor })
        defer { model.shutdown() }
        try await body(model, monitor, board, workspace, screen)
    }
}
