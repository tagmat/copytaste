import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Usage: make-icon.swift output.icns") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-" + UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let side = CGFloat(pixels)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: 36/255, green: 61/255, blue: 52/255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: side * 0.07, y: side * 0.07, width: side * 0.86, height: side * 0.86), xRadius: side * 0.19, yRadius: side * 0.19).fill()
        NSColor(red: 0.88, green: 0.76, blue: 0.51, alpha: 1).setStroke()
        let back = NSBezierPath(roundedRect: NSRect(x: side * 0.29, y: side * 0.38, width: side * 0.40, height: side * 0.36), xRadius: side * 0.06, yRadius: side * 0.06)
        back.lineWidth = side * 0.045
        back.stroke()
        NSColor(red: 36/255, green: 61/255, blue: 52/255, alpha: 1).setFill()
        let front = NSBezierPath(roundedRect: NSRect(x: side * 0.39, y: side * 0.27, width: side * 0.32, height: side * 0.34), xRadius: side * 0.06, yRadius: side * 0.06)
        front.fill()
        NSColor(red: 0.88, green: 0.76, blue: 0.51, alpha: 1).setStroke()
        front.lineWidth = side * 0.045
        front.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", folder.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("Icon conversion failed") }
