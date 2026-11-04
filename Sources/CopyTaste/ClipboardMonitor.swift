import AppKit
import Carbon
import ImageIO
import CopyTasteCore

struct ClipboardSource {
    let bundleID: String?
    let name: String?
    @MainActor static var current: ClipboardSource {
        let app = NSWorkspace.shared.frontmostApplication
        return ClipboardSource(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }
}

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int
    private var activationObserver: NSObjectProtocol?
    private var frontmostID: String?
    private var transitionUntil = Date.distantPast
    var policy = CapturePolicy()
    var captureImages = true
    var captureFiles = true
    var onCapture: ((ClipEntry) -> Void)?
    var onRejection: ((RejectionReason) -> Void)?
    var onMaintenance: (() -> Void)?
    private var ticks = 0
    private let sourceProvider: () -> ClipboardSource
    private let secureInputProvider: () -> Bool

    init(pasteboard: NSPasteboard = .general,
         sourceProvider: @escaping () -> ClipboardSource = { .current },
         secureInputProvider: @escaping () -> Bool = { IsSecureEventInputEnabled() }) {
        self.pasteboard = pasteboard
        self.sourceProvider = sourceProvider
        self.secureInputProvider = secureInputProvider
        lastChangeCount = pasteboard.changeCount
        frontmostID = sourceProvider().bundleID
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let identifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Discard the transition interval; the foreground app is only an attribution heuristic.
                self.frontmostID = identifier
                self.lastChangeCount = self.pasteboard.changeCount
                self.transitionUntil = Date().addingTimeInterval(0.6)
            }
        }
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount // Never import the pre-existing clipboard.
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func poll() {
        ticks += 1
        if ticks % 150 == 0 { onMaintenance?() }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return }
        let source = sourceProvider()
        let sourceID = source.bundleID
        var metadata = CaptureMetadata(sourceBundleID: sourceID, secureInput: secureInputProvider(),
            sourceChanged: sourceID != frontmostID || Date() < transitionUntil)
        if let rejection = policy.rejection(for: metadata) { onRejection?(rejection); return }
        let items = pasteboard.pasteboardItems ?? []
        metadata.types = Set(items.flatMap { $0.types.map(\.rawValue) })
        metadata.itemCount = items.count
        if let rejection = policy.rejection(for: metadata) { onRejection?(rejection); return }
        // Source markers are hints, never authority for allowing a protected foreground app.
        metadata.claimedSourceBundleID = pasteboard.string(forType: .init("org.nspasteboard.source"))
        if let rejection = policy.rejection(for: metadata) { onRejection?(rejection); return }
        guard let sourceID, let item = items.first else { return }
        var entry: ClipEntry?
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic"), .init("com.compuserve.gif"), .init("org.webmproject.webp"), .init("com.microsoft.bmp")]
        let imageType = imageTypes.first { item.types.contains($0) }
        // A browser can advertise both pixels and a URL. The pixels are the copied image.
        if item.types.contains(.fileURL) {
            guard captureFiles, let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL else { onRejection?(.unsupported); return }
            guard !CapturePolicy.isProtectedFileName(url.lastPathComponent) else { onRejection?(.secret); return }
            do {
                let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true else { onRejection?(.unsupported); return }
                guard let size = info.fileSize, size <= CapturePolicy.maxFileBytes else { onRejection?(.tooLarge); return }
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= CapturePolicy.maxFileBytes else { onRejection?(.tooLarge); return }
                if let reason = policy.rejection(forFile: bytes, name: url.lastPathComponent) { onRejection?(reason); return }
                entry = ClipEntry(kind: .file, fileData: bytes, fileName: url.lastPathComponent,
                    sourceName: source.name ?? "Application", sourceBundleID: sourceID)
            } catch { onRejection?(.unsupported); return }
        } else if let imageType {
            guard captureImages else { onRejection?(.unsupported); return }
            guard let data = item.data(forType: imageType) else { onRejection?(.unsupported); return }
            guard data.count <= CapturePolicy.maxImageBytes else { onRejection?(.tooLarge); return }
            // Inspect dimensions before allocating a decoded bitmap.
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8_192, height <= 8_192, width * height <= 16_000_000,
                  let image = NSBitmapImageRep(data: data),
                  let png = image.representation(using: .png, properties: [:]),
                  png.count <= CapturePolicy.maxImageBytes else { onRejection?(.unsupported); return }
            entry = ClipEntry(kind: .image, imageData: png,
                              sourceName: source.name ?? "Application", sourceBundleID: sourceID)
        } else if let text = item.string(forType: .string) ?? item.string(forType: .URL) {
            if let rejection = policy.rejection(forText: text) { onRejection?(rejection); return }
            entry = ClipEntry(kind: CapturePolicy.kind(for: text), text: text,
                              sourceName: source.name ?? "Application", sourceBundleID: sourceID)
        }
        guard pasteboard.changeCount == count,
              sourceProvider().bundleID == sourceID,
              !secureInputProvider() else { onRejection?(.sourceChanged); return }
        if let entry { onCapture?(entry) }
    }
}
