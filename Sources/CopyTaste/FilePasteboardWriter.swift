import AppKit

// Delegate URL representations to AppKit, allowing the pasteboard service to
// provide sandbox transfer information instead of inventing a file-URL string.
final class FilePasteboardWriter: NSObject, NSPasteboardWriting {
    private let url: NSURL
    private static let origin = NSPasteboard.PasteboardType("net.tagmat.copytaste.origin")
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    init(url: URL) { self.url = url as NSURL }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        url.writableTypes(for: pasteboard) + [Self.origin, Self.concealed]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == Self.origin { return "CopyTaste" }
        if type == Self.concealed { return Data() }
        return url.pasteboardPropertyList(forType: type)
    }
}
