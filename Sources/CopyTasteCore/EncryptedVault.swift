import Foundation
import CryptoKit
import Darwin

public enum VaultError: Error, LocalizedError {
    case oversized, unsupportedVersion, unsafePath
    public var errorDescription: String? {
        switch self {
        case .oversized: "The vault exceeds the size limit."
        case .unsupportedVersion: "This vault version is not supported."
        case .unsafePath: "The vault location is not a safe regular file."
        }
    }
}

public struct EncryptedVault: Sendable {
    public let url: URL
    private static let context = Data("net.tagmat.copytaste.vault.v1".utf8)
    public init(url: URL) { self.url = url }

    public func load(key: SymmetricKey) throws -> VaultSnapshot {
        try validatePath()
        guard FileManager.default.fileExists(atPath: url.path) else { return VaultSnapshot() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 40 * 1_024 * 1_024 else { throw VaultError.oversized }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let plaintext = try AES.GCM.open(sealed, using: key, authenticating: Self.context)
        let snapshot = try JSONDecoder().decode(VaultSnapshot.self, from: plaintext)
        guard snapshot.version == 1 else { throw VaultError.unsupportedVersion }
        return snapshot
    }

    public func save(_ snapshot: VaultSnapshot, key: SymmetricKey) throws {
        try validatePath()
        guard snapshot.version == 1 else { throw VaultError.unsupportedVersion }
        let plaintext = try JSONEncoder().encode(snapshot)
        guard plaintext.count <= 36 * 1_024 * 1_024 else { throw VaultError.oversized }
        let encrypted = try AES.GCM.seal(plaintext, using: key, authenticating: Self.context)
        guard let data = encrypted.combined else { throw VaultError.oversized }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Only ciphertext is ever written; atomic replacement leaves the prior vault intact on failure.
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }

    private func validatePath() throws {
        for path in [url.deletingLastPathComponent(), url] {
            var info = stat()
            let status = path.path.withCString { lstat($0, &info) }
            if status == 0 && (info.st_mode & S_IFMT) == S_IFLNK { throw VaultError.unsafePath }
        }
    }
}
