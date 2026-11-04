import XCTest
import CopyTasteCore

final class PreviewFormattingTests: XCTestCase {
    func testMarkdownHeadingsListsAndFencedCodeAreRenderedAsBlocks() {
        let source = "# A heading\n\nA **bold** thought.\n\n- First\n- Second\n\n```swift\nlet answer = 42\n```"
        let blocks = PreviewFormatting.markdown(source)
        XCTAssertTrue(blocks.contains(.heading(1, "A heading")))
        XCTAssertTrue(blocks.contains(.list("First")))
        XCTAssertTrue(blocks.contains(.code("swift", "let answer = 42")))
    }

    func testUnclosedFenceIsKeptWithoutLosingTheCode() {
        XCTAssertEqual(PreviewFormatting.markdown("```python\nreturn 7"), [.code("python", "return 7")])
    }

    func testKnownExtensionsTakePrecedenceOverAmbiguousFormatting() {
        XCTAssertTrue(PreviewFormatting.isMarkdown("ordinary text", fileName: "README.md"))
        XCTAssertFalse(PreviewFormatting.isMarkdown("# A comment", fileName: "script.py"))
        XCTAssertTrue(PreviewFormatting.isCode("# A comment", fileName: "script.py"))
        XCTAssertTrue(PreviewFormatting.isCode(#"{"answer":42}"#))
        XCTAssertFalse(PreviewFormatting.isCode("A quiet afternoon."))
    }

    func testStringsAndCommentsKeepTheirOwnTokens() {
        let source = "let value = \"return 42\" // let is a keyword\nreturn value"
        let ns = source as NSString
        let tokens = CodeTokenizer.tokens(in: source)
        XCTAssertTrue(tokens.contains { $0.kind == .string && ns.substring(with: $0.range) == "\"return 42\"" })
        XCTAssertTrue(tokens.contains { $0.kind == .comment && ns.substring(with: $0.range).hasPrefix("// let") })
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.count, 2)
    }

    func testUnicodeRangesStayValidAndPreviewWorkIsBounded() {
        let text = "let title = \"Merhaba dünya 🌍\"\nreturn title"
        let ns = text as NSString
        for token in CodeTokenizer.tokens(in: text) { XCTAssertLessThanOrEqual(NSMaxRange(token.range), ns.length) }
        XCTAssertLessThanOrEqual(PreviewFormatting.markdown(String(repeating: "- item\n", count: 10_000)).count, 25)
    }

    func testLayoutPreferenceRoundTripsWithoutChangingStorage() throws {
        var preferences = Preferences()
        preferences.storageMode = .iCloud
        preferences.selectorLayout = .orbit
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.selectorLayout, .orbit)
        XCTAssertEqual(restored.storageMode, .iCloud)
    }
}
