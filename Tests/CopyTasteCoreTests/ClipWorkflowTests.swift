import CopyTasteCore
import XCTest
@testable import CopyTaste

final class ClipWorkflowTests: XCTestCase {
    func testBatchPreservesSelectionOrderAndRejectsNonTextAndOversize() {
        let first = clip("First note")
        let second = clip("Second note")
        let image = ClipEntry(kind: .image, imageData: Data([0]), sourceName: "Fixture", sourceBundleID: "org.example.editor")
        let full = clip(String(repeating: "a", count: CapturePolicy.maxTextBytes))
        XCTAssertEqual(ClipBatch.text([second, first], separator: .tabs), "Second note\tFirst note")
        XCTAssertNil(ClipBatch.text([first, image], separator: .lines))
        XCTAssertNil(ClipBatch.text([full, first], separator: .lines))
    }

    func testPinProtectionIsOptInAndStillObeysCapacity() {
        let now = Date()
        var pin = clip("Old pinned note")
        pin.createdAt = now.addingTimeInterval(-8 * 86_400)
        pin.isPinned = true
        let recent = clip("Recent note")
        let snapshot = VaultSnapshot(entries: [recent, pin])
        var settings = Preferences()
        settings.maximumEntries = 1
        XCTAssertEqual(History.pruned(snapshot, preferences: settings, now: now).entries.map(\.id), [recent.id])
        settings.keepPinsPastExpiry = true
        XCTAssertEqual(History.pruned(snapshot, preferences: settings, now: now).entries.map(\.id), [pin.id])
    }

    func testImageSearchUsesEphemeralTextAndMatchesSourceTerms() {
        let image = ClipEntry(kind: .image, imageData: Data([0]), sourceName: "Fixture", sourceBundleID: "org.example.editor")
        XCTAssertTrue(History.search([image], query: "Golden").isEmpty)
        XCTAssertEqual(History.search([image], query: "golden fixture", imageText: [image.id: "Golden hour"]).map(\.id), [image.id])
        XCTAssertNil(image.text)
    }

    @MainActor func testRecognizesWordsRenderedIntoSyntheticImage() async throws {
        let entry = try XCTUnwrap(DemoContent.snapshot().entries.first { $0.kind == .image })
        let bytes = try XCTUnwrap(entry.imageData)
        let text = await ImageTextRecognition.shared.recognize(bytes)
        XCTAssertTrue(text?.localizedStandardContains("Golden hour study") == true)
    }

    private func clip(_ text: String) -> ClipEntry {
        ClipEntry(kind: .text, text: text, sourceName: "Fixture", sourceBundleID: "org.example.editor")
    }
}
