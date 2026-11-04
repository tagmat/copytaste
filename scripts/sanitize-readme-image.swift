import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else { fatalError("Usage: sanitize-readme-image.swift input.png output.png") }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Could not read application capture") }
// Reencode pixels only: no EXIF, author, software, timestamp or source-path fields.
CGImageDestinationAddImage(destination, image, [:] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write sanitised capture") }

// ImageIO may add an EXIF colour-space record even when no properties are supplied.
// Retain only pixels, transparency and colour interpretation chunks.
let encoded = try Data(contentsOf: output)
let allowed: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "cHRM", "gAMA", "iCCP", "sRGB", "cICP", "sBIT"]
var clean = Data(encoded.prefix(8))
var offset = 8
while offset + 12 <= encoded.count {
    let size = (0..<4).reduce(0) { ($0 << 8) | Int(encoded[offset + $1]) }
    let end = offset + 12 + size
    guard end <= encoded.count, let kind = String(data: encoded[(offset + 4)..<(offset + 8)], encoding: .ascii) else {
        fatalError("Invalid PNG chunk")
    }
    if allowed.contains(kind) { clean.append(encoded[offset..<end]) }
    offset = end
}
guard offset == encoded.count else { fatalError("Invalid PNG length") }
try clean.write(to: output, options: .atomic)
