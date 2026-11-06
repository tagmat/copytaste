import Foundation
import AppKit
import CopyTasteCore

enum DemoContent {
    @MainActor static func snapshot() -> VaultSnapshot {
        let collection = ClipCollection(name: "Studio notes")
        let paletteFolder = ClipCollection(name: "Color studies")
        let now = Date()
        var entries = [
            ClipEntry(kind: .text, text: "Good ideas deserve\na second taste.\n\nA small place for the things you want to come back to. Keep the useful bits close, and let everything else go.", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-120), isPinned: true, collectionID: collection.id, title: "A little room for good ideas"),
            ClipEntry(kind: .link, text: "https://developer.apple.com/swift/", sourceName: "Safari", sourceBundleID: "com.apple.Safari", createdAt: now.addingTimeInterval(-480), title: "The language of possibility"),
            ClipEntry(kind: .text, text: "struct SmallThings {\n    let worthKeeping: [String]\n\n    func revisit() -> String {\n        worthKeeping.joined(separator: \" · \")\n    }\n}", sourceName: "Xcode", sourceBundleID: "com.apple.dt.Xcode", createdAt: now.addingTimeInterval(-900), isPinned: true, title: "SmallThings.swift"),
            ClipEntry(kind: .image, imageData: palette(), sourceName: "Preview", sourceBundleID: "com.apple.Preview", createdAt: now.addingTimeInterval(-1500), collectionID: collection.id, title: "An afternoon palette"),
            ClipEntry(kind: .text, text: "BDF27C", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-2_000), collectionID: paletteFolder.id),
            ClipEntry(kind: .text, text: "#5F65E7A0", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-2_100), collectionID: paletteFolder.id),
            ClipEntry(kind: .text, text: "#F9B", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-2_200)),
            ClipEntry(kind: .text, text: "Leave a little space between one idea and the next. That's usually where the interesting part happens.", sourceName: "TextEdit", sourceBundleID: "com.apple.TextEdit", createdAt: now.addingTimeInterval(-2500), title: "Space to think"),
            ClipEntry(kind: .link, text: "https://www.swift.org/documentation/", sourceName: "Safari", sourceBundleID: "com.apple.Safari", createdAt: now.addingTimeInterval(-3600)),
            ClipEntry(kind: .text, text: "Monday\n• Refine the collection\n• Review the small details\n• Make something worth keeping", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-7000), title: "A short list")
        ]
        entries.append(ClipEntry(kind: .file, fileData: Data("# Notes in motion\n\n**Local** by default.\n\n```swift\nlet orbit = [\"ideas\", \"images\"]\nreturn orbit.first\n```\n".utf8), fileName: "Release notes.md", sourceName: "Finder", sourceBundleID: "com.apple.finder", createdAt: now.addingTimeInterval(-3_800)))
        entries.append(ClipEntry(kind: .file, fileData: samplePDF(), fileName: "Project notes.pdf", sourceName: "Finder", sourceBundleID: "com.apple.finder", createdAt: now.addingTimeInterval(-4_000)))
        return VaultSnapshot(entries: entries, collections: [collection, paletteFolder])
    }

    @MainActor static func samplePDF() -> Data? {
        let data = NSMutableData()
        var rect = CGRect(x: 0, y: 0, width: 300, height: 400)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &rect, nil) else { return nil }
        context.beginPDFPage(nil)
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor); context.fill(rect)
        context.setFillColor(NSColor(red: 0.74, green: 1, blue: 0.53, alpha: 1).cgColor)
        context.fill(CGRect(x: 24, y: 292, width: 252, height: 78))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Project notes" as NSString).draw(at: NSPoint(x: 38, y: 320), withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .semibold), .foregroundColor: NSColor.black])
        ("A little room for what comes next.\n\nCopyTaste by tagmat\nSynthetic preview document" as NSString).draw(in: NSRect(x: 28, y: 100, width: 244, height: 155), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        return data as Data
    }

    @MainActor private static func palette() -> Data? {
        let image = NSImage(size: NSSize(width: 720, height: 420))
        image.lockFocus()
        let colors: [NSColor] = [NSColor(red: 0.30, green: 0.32, blue: 0.23, alpha: 1),
            NSColor(red: 0.76, green: 0.34, blue: 0.22, alpha: 1),
            NSColor(red: 0.90, green: 0.76, blue: 0.48, alpha: 1),
            NSColor(red: 0.92, green: 0.89, blue: 0.81, alpha: 1)]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSRect(x: index * 180, y: 0, width: 180, height: 420).fill()
        }
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 172, y: 42, width: 376, height: 72), xRadius: 8, yRadius: 8).fill()
        ("Golden hour study" as NSString).draw(at: NSPoint(x: 193, y: 61), withAttributes: [
            .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
