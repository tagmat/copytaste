import AppKit
import Carbon
import ImageIO
import CopyTasteCore

struct ClipboardSource: Sendable {
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
    private var generation = 0
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
                self.sourceDidActivate(identifier)
            }
        }
    }

    func sourceDidActivate(_ identifier: String?) {
        let count = pasteboard.changeCount
        if count != lastChangeCount { onRejection?(.sourceChanged) }
        generation += 1
        frontmostID = identifier
        lastChangeCount = count
        transitionUntil = Date().addingTimeInterval(0.6)
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount // Never import the pre-existing clipboard.
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
    }

    func stop() { generation += 1; timer?.invalidate(); timer = nil }

    func poll() async {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny || pasteboard.accessBehavior == .ask {
            onRejection?(.permissionRequired)
            return
        }
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
        guard sourceID != nil, let item = items.first else { return }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic"), .init("com.compuserve.gif"), .init("org.webmproject.webp"), .init("com.microsoft.bmp")]
        let payload: CapturePayload
        if let imageType = imageTypes.first(where: { item.types.contains($0) }) {
            guard captureImages, let data = item.data(forType: imageType) else { onRejection?(.unsupported); return }
            guard data.count <= CapturePolicy.maxImageBytes else { onRejection?(.tooLarge); return }
            payload = .image(data)
        } else if item.types.contains(.fileURL) {
            guard captureFiles, let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL else { onRejection?(.unsupported); return }
            guard !CapturePolicy.isProtectedFileName(url.lastPathComponent) else { onRejection?(.secret); return }
            payload = .file(url)
        } else if let text = item.string(forType: .string) ?? item.string(forType: .URL) {
            if let rejection = policy.rejection(forText: text) { onRejection?(rejection); return }
            payload = .text(text)
        } else { onRejection?(.unsupported); return }
        let epoch = generation
        let policy = policy
        let result = await Task.detached(priority: .utility) {
            payload.process(source: source, policy: policy)
        }.value
        guard generation == epoch else { return }
        guard pasteboard.changeCount == count,
              sourceProvider().bundleID == sourceID,
              !secureInputProvider() else { onRejection?(.sourceChanged); return }
        switch result {
        case .success(let entry): onCapture?(entry)
        case .failure(let reason): onRejection?(reason)
        }
    }
}

private enum CapturePayload: Sendable {
    case text(String), image(Data), file(URL)

    func process(source: ClipboardSource, policy: CapturePolicy) -> Result<ClipEntry, RejectionReason> {
        guard let sourceID = source.bundleID else { return .failure(.unknownSource) }
        switch self {
        case .text(let text):
            return .success(ClipEntry(kind: CapturePolicy.kind(for: text), text: text,
                sourceName: source.name ?? "Application", sourceBundleID: sourceID))
        case .file(let url):
            do {
                let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true else { return .failure(.unsupported) }
                guard let size = info.fileSize, size <= CapturePolicy.maxFileBytes else { return .failure(.tooLarge) }
                let bytes = try Data(contentsOf: url)
                if let rejection = policy.rejection(forFile: bytes, name: url.lastPathComponent) { return .failure(rejection) }
                return .success(ClipEntry(kind: .file, fileData: bytes, fileName: url.lastPathComponent,
                    sourceName: source.name ?? "Application", sourceBundleID: sourceID))
            } catch { return .failure(.unsupported) }
        case .image(let data):
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let info = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int,
                  let height = info[kCGImagePropertyPixelHeight] as? Int,
                  (1...8_192).contains(width), (1...8_192).contains(height), width * height <= 16_000_000 else { return .failure(.tooLarge) }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: min(4_000, max(width, height))]
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
                  image.width * image.height <= 16_000_000,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                  png.count <= CapturePolicy.maxImageBytes else { return .failure(.tooLarge) }
            return .success(ClipEntry(kind: .image, imageData: png,
                sourceName: source.name ?? "Application", sourceBundleID: sourceID))
        }
    }
}
