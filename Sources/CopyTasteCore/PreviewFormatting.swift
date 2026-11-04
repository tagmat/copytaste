import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, String), paragraph(String), list(String), quote(String), code(String, String), rule
}

public enum PreviewFormatting {
    public static func isMarkdown(_ text: String, fileName: String? = nil) -> Bool {
        let ext = ((fileName ?? "") as NSString).pathExtension.lowercased()
        if !ext.isEmpty { return ["md", "markdown", "mdown"].contains(ext) }
        return text.hasPrefix("# ") || text.hasPrefix("## ") || text.contains("```" ) || text.contains("\n- ")
    }

    public static func isCode(_ text: String, fileName: String? = nil) -> Bool {
        let ext = ((fileName ?? "") as NSString).pathExtension.lowercased()
        if ["swift", "js", "jsx", "ts", "tsx", "py", "rs", "go", "java", "c", "cpp", "h", "json", "yml", "yaml", "sh", "css", "html", "sql"].contains(ext) { return true }
        let trimmed = String(text.prefix(8_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#!") || trimmed.range(of: #"^(?:SELECT|INSERT|UPDATE|DELETE|CREATE)\s"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")), let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil { return true }
        return text.range(of: #"(?m)^\s*(?:struct|class|func|def|const|let|var|import|fn|public|return)\s+\w+"#, options: .regularExpression) != nil &&
            (text.contains("{") || text.contains("=") || text.contains("("))
    }

    public static func markdown(_ original: String) -> [MarkdownBlock] {
        let lines = String(original.prefix(8_000)).components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: String?
        var language = ""
        func flushParagraph() { if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] } }
        for raw in lines.prefix(120) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let delimiter = fence {
                if line.hasPrefix(delimiter) { blocks.append(.code(language, code.joined(separator: "\n"))); code = []; fence = nil }
                else { code.append(raw) }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph(); fence = String(line.prefix(3)); language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.isEmpty { flushParagraph() }
            else if line == "---" || line == "***" { flushParagraph(); blocks.append(.rule) }
            else if line.hasPrefix("#"), let space = line.firstIndex(of: " "), line[..<space].allSatisfy({ $0 == "#" }) {
                flushParagraph(); blocks.append(.heading(min(6, line.distance(from: line.startIndex, to: space)), String(line[line.index(after: space)...])))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph(); blocks.append(.list(String(line.dropFirst(2))))
            } else if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                flushParagraph(); blocks.append(.list(String(line[range.upperBound...])))
            } else if line.hasPrefix("> ") { flushParagraph(); blocks.append(.quote(String(line.dropFirst(2)))) }
            else { paragraph.append(line) }
            if blocks.count >= 24 { break }
        }
        flushParagraph()
        if fence != nil { blocks.append(.code(language, code.joined(separator: "\n"))) }
        return blocks
    }
}

public enum CodeTokenKind: String, Sendable { case comment, string, number, keyword, function }
public struct CodeToken: Equatable, Sendable {
    public var range: NSRange
    public var kind: CodeTokenKind
}

public enum CodeTokenizer {
    private static let expression = try! NSRegularExpression(pattern: #"(?<comment>//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/)|(?<string>\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')|(?<number>\b\d+(?:\.\d+)?\b)|(?<keyword>\b(?:let|var|func|struct|class|enum|protocol|extension|import|return|if|else|guard|for|while|switch|case|break|continue|true|false|nil|null|const|function|export|from|async|await|try|catch|throw|def|self|in|public|private|static|final|mutating|fn|impl|use|SELECT|FROM|WHERE)\b)|(?<function>\b[A-Za-z_][A-Za-z_0-9]*(?=\s*\())"#)

    public static func tokens(in text: String) -> [CodeToken] {
        let text = String(text.prefix(8_000))
        let kinds: [CodeTokenKind] = [.comment, .string, .number, .keyword, .function]
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            for kind in kinds {
                let range = match.range(withName: kind.rawValue)
                if range.location != NSNotFound { return CodeToken(range: range, kind: kind) }
            }
            return nil
        }
    }
}
