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
    var captureImages = false
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
        let source = sourceProvider()
        let sourceID = source.bundleID
        let items = pasteboard.pasteboardItems ?? []
        let types = Set(items.flatMap { $0.types.map(\.rawValue) })
        var metadata = CaptureMetadata(sourceBundleID: sourceID, types: types,
            secureInput: secureInputProvider(),
            sourceChanged: sourceID != frontmostID || Date() < transitionUntil,
            itemCount: items.count)
        if let rejection = policy.rejection(for: metadata) { onRejection?(rejection); return }
        // Source markers are hints, never authority for allowing a protected foreground app.
        metadata.claimedSourceBundleID = pasteboard.string(forType: .init("org.nspasteboard.source"))
        if let rejection = policy.rejection(for: metadata) { onRejection?(rejection); return }
        guard let sourceID, let item = items.first else { return }
        var entry: ClipEntry?
        if let text = item.string(forType: .string) {
            if let rejection = policy.rejection(forText: text) { onRejection?(rejection); return }
            entry = ClipEntry(kind: CapturePolicy.kind(for: text), text: text,
                              sourceName: source.name ?? "Application", sourceBundleID: sourceID)
        } else if captureImages, let data = item.data(forType: .png) ?? item.data(forType: .tiff) {
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
        }
        guard pasteboard.changeCount == count,
              sourceProvider().bundleID == sourceID,
              !secureInputProvider() else { onRejection?(.sourceChanged); return }
        if let entry { onCapture?(entry) }
    }
}
