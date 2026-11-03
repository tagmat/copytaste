import Foundation
import AppKit
import CopyTasteCore

enum DemoContent {
    @MainActor static func snapshot() -> VaultSnapshot {
        let collection = ClipCollection(name: "Studio notes")
        let now = Date()
        var entries = [
            ClipEntry(kind: .text, text: "Good ideas deserve\na second taste.\n\nA small place for the things you want to come back to. Keep the useful bits close, and let everything else go.", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-120), isPinned: true, collectionID: collection.id, title: "A little room for good ideas"),
            ClipEntry(kind: .link, text: "https://developer.apple.com/swift/", sourceName: "Safari", sourceBundleID: "com.apple.Safari", createdAt: now.addingTimeInterval(-480), title: "The language of possibility"),
            ClipEntry(kind: .text, text: "struct SmallThings {\n    let worthKeeping: [String]\n\n    func revisit() -> String {\n        worthKeeping.joined(separator: \" · \")\n    }\n}", sourceName: "Xcode", sourceBundleID: "com.apple.dt.Xcode", createdAt: now.addingTimeInterval(-900), isPinned: true, title: "SmallThings.swift"),
            ClipEntry(kind: .image, imageData: palette(), sourceName: "Preview", sourceBundleID: "com.apple.Preview", createdAt: now.addingTimeInterval(-1500), collectionID: collection.id, title: "An afternoon palette"),
            ClipEntry(kind: .text, text: "Leave a little space between one idea and the next. That's usually where the interesting part happens.", sourceName: "TextEdit", sourceBundleID: "com.apple.TextEdit", createdAt: now.addingTimeInterval(-2500), title: "Space to think"),
            ClipEntry(kind: .link, text: "https://www.swift.org/documentation/", sourceName: "Safari", sourceBundleID: "com.apple.Safari", createdAt: now.addingTimeInterval(-3600)),
            ClipEntry(kind: .text, text: "Monday\n• Refine the collection\n• Review the small details\n• Make something worth keeping", sourceName: "Notes", sourceBundleID: "com.apple.Notes", createdAt: now.addingTimeInterval(-7000), title: "A short list")
        ]
        entries[0].lastUsedAt = now
        return VaultSnapshot(entries: entries, collections: [collection])
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
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
