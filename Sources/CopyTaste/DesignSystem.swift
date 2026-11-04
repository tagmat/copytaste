import SwiftUI
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CopyTasteCore

enum Palette {
    static let background = Color(red: 0.055, green: 0.072, blue: 0.085)
    static let surface = Color(red: 0.085, green: 0.105, blue: 0.12)
    static let raised = Color(red: 0.13, green: 0.16, blue: 0.18)
    static let text = Color(red: 0.94, green: 0.97, blue: 0.96)
    static let secondary = Color(red: 0.65, green: 0.72, blue: 0.75)
    static let mint = Color(red: 0.74, green: 1, blue: 0.53)
    static let violet = Color(red: 0.73, green: 0.65, blue: 1)
}

struct BrandMark: View {
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: "square.on.square").font(.system(size: size * 0.54, weight: .medium))
            .foregroundStyle(Palette.mint).frame(width: size, height: size)
            .background(Palette.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.3)).accessibilityHidden(true)
    }
}

struct FrostedSurface: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content.background(Palette.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.1), lineWidth: 0.7))
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Palette.background : Palette.text).frame(width: 34, height: 34)
                .background(active ? Palette.mint : .white.opacity(0.065), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

extension ClipKind {
    var symbol: String {
        switch self { case .text: "text.alignleft"; case .link: "link"; case .image: "photo"; case .file: "doc" }
    }
    var label: String {
        switch self { case .text: "Text"; case .link: "Link"; case .image: "Image"; case .file: "File" }
    }
}

@MainActor final class PreviewCache {
    static let shared = PreviewCache()
    private let images = NSCache<NSString, NSImage>()
    init() { images.countLimit = 40; images.totalCostLimit = 24 * 1_024 * 1_024 }

    func thumbnail(_ entry: ClipEntry) -> NSImage? {
        let key = entry.id.uuidString as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let data = entry.imageData ?? entry.fileData else { return nil }
        var image: NSImage?
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0, width <= 8_192, height <= 8_192, width * height <= 16_000_000 {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 560, kCGImageSourceCreateThumbnailWithTransform: true]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { image = NSImage(cgImage: cg, size: .zero) }
        } else if entry.fileName?.lowercased().hasSuffix(".pdf") == true {
            if let document = PDFDocument(data: data), let page = document.page(at: 0) {
                image = withExtendedLifetime(document) { page.thumbnail(of: NSSize(width: 420, height: 320), for: .cropBox) }
            }
        }
        if let image { images.setObject(image, forKey: key, cost: 560 * 400 * 4) }
        return image
    }

    func removeAll() { images.removeAllObjects() }
}

struct FilePreview: View {
    let entry: ClipEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preview = PreviewCache.shared.thumbnail(entry) {
                Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 126)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            } else if let data = entry.fileData, CapturePolicy.isTextFile(entry.fileName ?? ""), data.count <= CapturePolicy.maxTextBytes {
                let text = String(decoding: data.prefix(8_000), as: UTF8.self)
                Group {
                    if PreviewFormatting.isMarkdown(text, fileName: entry.fileName) { MarkdownPreview(source: text) }
                    else if PreviewFormatting.isCode(text, fileName: entry.fileName) { CodePreview(source: text) }
                    else { Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(6) }
                }.frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 126, alignment: .topLeading).clipped()
            } else {
                let ext = ((entry.fileName ?? "") as NSString).pathExtension
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data))
                    .resizable().scaledToFit().frame(width: 70, height: 84).frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            Text(entry.fileName ?? "File").font(.system(size: 15, weight: .medium)).lineLimit(2)
            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }
    }
}
