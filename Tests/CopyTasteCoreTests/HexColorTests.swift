import CopyTasteCore
import XCTest
@testable import CopyTaste

final class HexColorTests: XCTestCase {
    func testShorthandAndAlphaExpandAndPreserveChannelOrder() throws {
        let short = try XCTUnwrap(HexColor(" #aBc8\n"))
        XCTAssertEqual(short.hex, "#AABBCC88")
        XCTAssertEqual(short.cssRGB, "rgba(170, 187, 204, 0.533)")
        XCTAssertEqual(HexColor("#12345600")?.alpha, 0)
        XCTAssertEqual(HexColor("#f9b")?.hex, "#FF99BB")
        XCTAssertEqual(HexColor("#123456")?.cssRGB, "rgb(18, 52, 86)")
    }

    func testColorFilterAndSearchUseExistingTextClipsWithoutChangingTheirPayload() {
        let clip = ClipEntry(kind: .text, text: "#bdf", sourceName: "Fixture", sourceBundleID: "org.example.editor")
        var invalid = clip
        invalid.text = "Color: #bdf"
        XCTAssertTrue(PickerFilter.colors.includes(clip))
        XCTAssertFalse(PickerFilter.colors.includes(invalid))
        XCTAssertNil(HexColor("#+ab"))
        XCTAssertNil(HexColor("#abcd0"))
        XCTAssertEqual(History.search([clip], query: "#BBDDFF").first?.text, "#bdf")
    }
}
