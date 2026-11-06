import SwiftUI
import AppKit
import CopyTasteCore

struct CodePreview: View {
    let source: String
    var lines = 7
    var fileName: String?
    var body: some View {
        Text(highlighted).font(.system(size: 11, design: .monospaced)).lineSpacing(3).lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .topLeading).allowsHitTesting(false)
    }
    private var highlighted: AttributedString {
        let text = String(source.prefix(8_000))
        var value = AttributedString(text)
        value.foregroundColor = Palette.text
        for token in CodeTokenizer.tokens(in: text, fileName: fileName) {
            let color: Color
            switch token.kind {
            case .keyword: color = Palette.violet
            case .string: color = Palette.mint
            case .comment: color = Palette.secondary
            case .number: color = Color(red: 0.96, green: 0.81, blue: 0.57)
            case .function: color = Color(red: 0.55, green: 0.88, blue: 0.9)
            }
            if let range = Range(token.range, in: text), let lower = AttributedString.Index(range.lowerBound, within: value),
               let upper = AttributedString.Index(range.upperBound, within: value) { value[lower..<upper].foregroundColor = color }
        }
        return value
    }
}

struct MarkdownPreview: View {
    let source: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(PreviewFormatting.markdown(source).prefix(6).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(inline(text)).font(.system(size: level == 1 ? 17 : 14, weight: .semibold, design: .rounded)).lineLimit(2)
                case .paragraph(let text): Text(inline(text)).font(.system(size: 11)).lineLimit(3)
                case .list(let text): HStack(alignment: .top, spacing: 6) { Circle().fill(Palette.mint).frame(width: 3, height: 3).padding(.top, 5); Text(inline(text)).font(.system(size: 11)).lineLimit(2) }
                case .quote(let text): Text(inline(text)).font(.system(size: 11)).italic().foregroundStyle(Palette.secondary).lineLimit(2)
                case .code(let language, let text): CodePreview(source: text, lines: 5, fileName: "snippet." + language).padding(8).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                case .rule: Divider().overlay(Palette.secondary.opacity(0.3))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading).allowsHitTesting(false)
    }
    private func inline(_ text: String) -> AttributedString {
        // Parsing is local; linked text is inert inside a preview and images are never fetched.
        var value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in value.runs where run.link != nil { value[run.range].link = nil }
        return value
    }
}
