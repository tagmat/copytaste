import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, image, file
}

public struct ClipEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ClipKind
    public var text: String?
    public var imageData: Data?
    public var fileData: Data?
    public var fileName: String?
    public var sourceName: String
    public var sourceBundleID: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastUsedAt: Date?
    public var isPinned: Bool
    public var collectionID: UUID?
    public var title: String?

    public init(id: UUID = UUID(), kind: ClipKind, text: String? = nil,
                imageData: Data? = nil, fileData: Data? = nil, fileName: String? = nil, sourceName: String, sourceBundleID: String,
                createdAt: Date = Date(), isPinned: Bool = false,
                collectionID: UUID? = nil, title: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.fileData = fileData
        self.fileName = fileName
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
        if kind == .file { return fileName ?? "File" }
        return String((text ?? "").prefix(512).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first ?? "Text")
    }

    public var byteCount: Int { (text?.utf8.count ?? 0) + (imageData?.count ?? 0) + (fileData?.count ?? 0) }

    public var hexColor: HexColor? {
        guard kind == .text, let text else { return nil }
        return HexColor(text)
    }

    public var fingerprint: String {
        var data = Data(kind.rawValue.utf8)
        data.append(Data((text ?? "").utf8))
        data.append(imageData ?? Data())
        if kind == .file { data.append(Data((fileName ?? "").utf8)); data.append(0); data.append(fileData ?? Data()) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ClipCollection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var modifiedAt: Date?

    public init(id: UUID = UUID(), name: String, modifiedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.modifiedAt = modifiedAt
    }
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

public enum SelectorLayout: String, Codable, CaseIterable, Sendable {
    case pinnedAndRecent, orbit
}

public enum SelectorShortcut: String, Codable, CaseIterable, Sendable {
    case shiftCommand, optionCommand, controlOption, disabled

    public var label: String {
        switch self {
        case .shiftCommand: "⇧⌘V"
        case .optionCommand: "⌥⌘V"
        case .controlOption: "⌃⌥V"
        case .disabled: "Off"
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var captureEnabled = false
    public var captureImages = true
    public var captureFiles = true
    public var autoPaste = true
    public var selectorLayout: SelectorLayout = .pinnedAndRecent
    public var selectorShortcut: SelectorShortcut = .shiftCommand
    public var imageTextSearch = false
    public var keepPinsPastExpiry = false
    public var retentionDays = 7
    public var maximumEntries = 300
    public var clearClipboardAfterSeconds = 45
    public var excludedBundleIDs: Set<String> = []
    public var storageMode: StorageMode = .memory
    public var persistPinnedOnly = false
    public var customFolderPath: String?
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, captureEnabled, captureImages, captureFiles, autoPaste, selectorLayout, retentionDays, maximumEntries
        case clearClipboardAfterSeconds, excludedBundleIDs, storageMode, persistPinnedOnly, customFolderPath
        case selectorShortcut, imageTextSearch, keepPinsPastExpiry
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let oldVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        captureEnabled = try values.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? false
        // Version 0.2 enables image capture; subsequent explicit opt-outs are preserved.
        captureImages = oldVersion < 2 ? true : (try values.decodeIfPresent(Bool.self, forKey: .captureImages) ?? true)
        autoPaste = try values.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true
        captureFiles = try values.decodeIfPresent(Bool.self, forKey: .captureFiles) ?? true
        selectorLayout = (try? values.decodeIfPresent(SelectorLayout.self, forKey: .selectorLayout)) ?? .pinnedAndRecent
        selectorShortcut = (try? values.decodeIfPresent(SelectorShortcut.self, forKey: .selectorShortcut)) ?? .shiftCommand
        imageTextSearch = (try? values.decodeIfPresent(Bool.self, forKey: .imageTextSearch)) ?? false
        keepPinsPastExpiry = (try? values.decodeIfPresent(Bool.self, forKey: .keepPinsPastExpiry)) ?? false
        retentionDays = try values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 7
        maximumEntries = try values.decodeIfPresent(Int.self, forKey: .maximumEntries) ?? 300
        clearClipboardAfterSeconds = try values.decodeIfPresent(Int.self, forKey: .clearClipboardAfterSeconds) ?? 45
        excludedBundleIDs = try values.decodeIfPresent(Set<String>.self, forKey: .excludedBundleIDs) ?? []
        storageMode = try values.decodeIfPresent(StorageMode.self, forKey: .storageMode) ?? .memory
        persistPinnedOnly = try values.decodeIfPresent(Bool.self, forKey: .persistPinnedOnly) ?? false
        customFolderPath = try values.decodeIfPresent(String.self, forKey: .customFolderPath)
    }
}
