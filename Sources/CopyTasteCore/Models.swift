import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, image
}

public struct ClipEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ClipKind
    public var text: String?
    public var imageData: Data?
    public var sourceName: String
    public var sourceBundleID: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastUsedAt: Date?
    public var isPinned: Bool
    public var collectionID: UUID?
    public var title: String?

    public init(id: UUID = UUID(), kind: ClipKind, text: String? = nil,
                imageData: Data? = nil, sourceName: String, sourceBundleID: String,
                createdAt: Date = Date(), isPinned: Bool = false,
                collectionID: UUID? = nil, title: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.isPinned = isPinned
        self.collectionID = collectionID
        self.title = title
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if kind == .image { return "Image" }
        return String((text ?? "").split(separator: "\n", omittingEmptySubsequences: true).first ?? "Text")
    }

    public var byteCount: Int { (text?.utf8.count ?? 0) + (imageData?.count ?? 0) }

    public var fingerprint: String {
        var data = Data(kind.rawValue.utf8)
        data.append(Data((text ?? "").utf8))
        data.append(imageData ?? Data())
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ClipCollection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct VaultSnapshot: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var entries: [ClipEntry]
    public var collections: [ClipCollection]
    public init(entries: [ClipEntry] = [], collections: [ClipCollection] = []) {
        self.entries = entries
        self.collections = collections
    }
}

public enum StorageMode: String, Codable, CaseIterable, Sendable {
    case memory, encryptedLocal, encryptedFolder, iCloud
}

public struct Preferences: Codable, Equatable, Sendable {
    public var captureEnabled = false
    public var captureImages = false
    public var retentionDays = 7
    public var maximumEntries = 300
    public var clearClipboardAfterSeconds = 45
    public var excludedBundleIDs: Set<String> = []
    public var storageMode: StorageMode = .memory
    public var persistPinnedOnly = false
    public var customFolderPath: String?
    public init() {}
}
