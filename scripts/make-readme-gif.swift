import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// Assemble a tour from application-only captures containing synthetic sample clips.
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else { fatalError("Usage: make-readme-gif.swift output.gif input.png input.png ...") }
let output = URL(fileURLWithPath: args[0])
let inputs = args.dropFirst().map { URL(fileURLWithPath: $0) }
let width = 1120
let height = 600
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, inputs.count, nil) else { fatalError("Could not create GIF") }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for input in inputs {
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not read a capture") }
    context.setFillColor(CGColor(red: 0.055, green: 0.072, blue: 0.085, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let ratio = min(CGFloat(width - 28) / CGFloat(image.width), CGFloat(height - 28) / CGFloat(image.height))
    let box = CGRect(x: (CGFloat(width) - CGFloat(image.width) * ratio) / 2,
        y: (CGFloat(height) - CGFloat(image.height) * ratio) / 2,
        width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
    context.interpolationQuality = .high
    context.draw(image, in: box)
    guard let frame = context.makeImage() else { fatalError("Could not draw a capture") }
    // New pixel frames intentionally carry no source metadata or local paths.
    CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 2.4]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Could not finish GIF") }
print("Created synthetic interface tour: \(inputs.count) frames")
