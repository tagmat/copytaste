import XCTest
@testable import CopyTaste

final class PasteServiceTests: XCTestCase {
    @MainActor func testCopyThenActivateThenPasteInTheOriginalProcess() async {
        var calls: [String] = []
        let service = PasteService(trusted: { true }, secureInput: { false }, frontmostPID: { 42 },
            activate: { _ in calls.append("activate"); return true }, send: { _ in calls.append("paste") }, settle: {})
        let outcome = await service.perform(copy: { calls.append("copy"); return true },
            destination: PasteDestination(processID: 42, name: "Fixture"), automatic: true, demo: false)
        XCTAssertEqual(calls, ["copy", "activate", "paste"])
        XCTAssertEqual(outcome, .pasted)
    }

    @MainActor func testDemoNeverActivatesOrPostsEvents() async {
        var sent = false
        let service = PasteService(trusted: { true }, secureInput: { false }, frontmostPID: { 42 },
            activate: { _ in sent = true; return true }, send: { _ in sent = true }, settle: {})
        let outcome = await service.perform(copy: { true }, destination: PasteDestination(processID: 42, name: "Fixture"), automatic: true, demo: true)
        XCTAssertEqual(outcome, .copied)
        XCTAssertFalse(sent)
    }

    @MainActor func testPermissionFailureLeavesACopyWithoutPosting() async {
        var sent = false
        let service = PasteService(trusted: { false }, send: { _ in sent = true }, settle: {})
        let outcome = await service.perform(copy: { true }, destination: PasteDestination(processID: 42, name: "Fixture"), automatic: true, demo: false)
        XCTAssertEqual(outcome, .permissionRequired)
        XCTAssertFalse(sent)
    }

    @MainActor func testChangedDestinationAndInvalidatedSessionNeverPaste() async {
        var sent = false
        let service = PasteService(trusted: { true }, secureInput: { false }, frontmostPID: { 99 },
            activate: { _ in true }, send: { _ in sent = true }, settle: {})
        let outcome = await service.perform(copy: { true }, destination: PasteDestination(processID: 42, name: "Fixture"), automatic: true, demo: false)
        XCTAssertEqual(outcome, .destinationChanged)
        XCTAssertFalse(sent)
    }

    @MainActor func testFailedCopyAndSecureInputPreventPosting() async {
        var sent = false
        let service = PasteService(trusted: { true }, secureInput: { true }, frontmostPID: { 42 },
            activate: { _ in true }, send: { _ in sent = true }, settle: {})
        let failed = await service.perform(copy: { false }, destination: nil, automatic: true, demo: false)
        let secure = await service.perform(copy: { true }, destination: PasteDestination(processID: 42, name: "Fixture"), automatic: true, demo: false)
        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(secure, .copied)
        XCTAssertFalse(sent)
    }

    @MainActor func testLockWhileDestinationActivatesCancelsPaste() async {
        var valid = true
        var sent = false
        let service = PasteService(trusted: { true }, secureInput: { false }, frontmostPID: { 42 },
            activate: { _ in true }, send: { _ in sent = true }, settle: { valid = false })
        let outcome = await service.perform(copy: { true }, destination: PasteDestination(processID: 42, name: "Fixture"),
            automatic: true, demo: false, stillValid: { valid })
        XCTAssertEqual(outcome, .destinationChanged)
        XCTAssertFalse(sent)
    }
}
