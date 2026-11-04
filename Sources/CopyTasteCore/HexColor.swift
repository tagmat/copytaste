import Foundation

public struct HexColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init?(_ text: String) {
        guard text.utf8.prefix(65).count <= 64 else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.first == "#" else { return nil }
        let digits = value.dropFirst().utf8
        let count = digits.count
        guard [3, 4, 6, 8].contains(count),
              digits.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let code = UInt32(value.dropFirst(), radix: 16) else { return nil }
        let shorthand = count <= 4
        let hasAlpha = count == 4 || count == 8
        let bitsPerChannel = shorthand ? 4 : 8
        let mask: UInt32 = shorthand ? 15 : 255
        let multiplier: UInt32 = shorthand ? 17 : 1
        func channel(_ index: Int) -> UInt8 {
            UInt8(((code >> (index * bitsPerChannel)) & mask) * multiplier)
        }
        red = channel(hasAlpha ? 3 : 2)
        green = channel(hasAlpha ? 2 : 1)
        blue = channel(hasAlpha ? 1 : 0)
        alpha = hasAlpha ? channel(0) : 255
    }

    public var hex: String {
        let rgb = String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
        return alpha == 255 ? rgb : rgb + String(format: "%02X", Int(alpha))
    }

    public var cssRGB: String {
        let channels = "\(red), \(green), \(blue)"
        guard alpha != 255 else { return "rgb(\(channels))" }
        let opacity = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(alpha) / 255)
        return "rgba(\(channels), \(opacity))"
    }
}
