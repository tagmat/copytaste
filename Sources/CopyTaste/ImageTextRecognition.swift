import CopyTasteCore
import Foundation
import ImageIO
import Vision

actor ImageTextRecognition {
    static let shared = ImageTextRecognition()

    func recognize(_ data: Data) -> String? {
        guard !Task.isCancelled, data.count <= CapturePolicy.maxImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...8_192).contains(width), (1...8_192).contains(height),
              width * height <= 16_000_000 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_800
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { return nil }
        guard !Task.isCancelled else { return nil }
        let lines = (request.results ?? []).prefix(96).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.contains(where: CapturePolicy.containsSecret) else { return nil }
        let result = String(lines.joined(separator: "\n").prefix(4_096))
        return CapturePolicy().rejection(forText: result) == nil ? result : nil
    }
}
