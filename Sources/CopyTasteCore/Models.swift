import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, image, file
}

public struct ClipEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ClipKind { didSet { refreshFingerprint() } }
    public var text: String? { didSet { refreshFingerprint() } }
    public var imageData: Data? { didSet { refreshFingerprint() } }
    public var fileData: Data? { didSet { refreshFingerprint() } }
    public var fileName: String? { didSet { refreshFingerprint() } }
    public var sourceName: String
    public var sourceBundleID: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var isPinned: Bool
    public var collectionID: UUID?
    public var title: String?
    private var contentFingerprint = ""

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
        refreshFingerprint()
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

    public var fingerprint: String { contentFingerprint }

    private mutating func refreshFingerprint() {
        var hash = SHA256()
        hash.update(data: Data(kind.rawValue.utf8))
        if let text { hash.update(data: Data(text.utf8)) }
        if let imageData { hash.update(data: imageData) }
        if kind == .file {
            hash.update(data: Data((fileName ?? "").utf8))
            hash.update(data: Data([0]))
            if let fileData { hash.update(data: fileData) }
        }
        let digits = Array("0123456789abcdef".utf8)
        contentFingerprint = String(decoding: hash.finalize().flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }, as: UTF8.self)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageData, fileData, fileName, sourceName, sourceBundleID
        case createdAt, modifiedAt, isPinned, collectionID, title
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(ClipKind.self, forKey: .kind)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        imageData = try values.decodeIfPresent(Data.self, forKey: .imageData)
        fileData = try values.decodeIfPresent(Data.self, forKey: .fileData)
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
        sourceName = try values.decode(String.self, forKey: .sourceName)
        sourceBundleID = try values.decode(String.self, forKey: .sourceBundleID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
        collectionID = try values.decodeIfPresent(UUID.self, forKey: .collectionID)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        refreshFingerprint()
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
    public var clearHistoryOnSessionLock = false
    public var retentionDays = 7
    public var maximumEntries = 300
    public var clearClipboardAfterSeconds = 45
    public var excludedBundleIDs: Set<String> = []
    public var storageMode: StorageMode = .memory
    public var persistPinnedOnly = false
    public var customFolderPath: String?
    public private(set) var recoveryWarnings: [String] = []
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, captureEnabled, captureImages, captureFiles, autoPaste, selectorLayout, retentionDays, maximumEntries
        case clearClipboardAfterSeconds, excludedBundleIDs, storageMode, persistPinnedOnly, customFolderPath
        case selectorShortcut, imageTextSearch, keepPinsPastExpiry, clearHistoryOnSessionLock
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ type: T.Type, _ key: CodingKeys, _ fallback: T) -> T {
            guard values.contains(key) else { return fallback }
            do { return try values.decode(T.self, forKey: key) }
            catch { recoveryWarnings.append(key.stringValue); return fallback }
        }
        let oldVersion = read(Int.self, .schemaVersion, 1)
        captureEnabled = read(Bool.self, .captureEnabled, false)
        // Version 0.2 enables image capture; subsequent explicit opt-outs are preserved.
        captureImages = oldVersion < 2 ? true : read(Bool.self, .captureImages, true)
        autoPaste = read(Bool.self, .autoPaste, true)
        captureFiles = read(Bool.self, .captureFiles, oldVersion >= 2)
        selectorLayout = read(SelectorLayout.self, .selectorLayout, .pinnedAndRecent)
        selectorShortcut = read(SelectorShortcut.self, .selectorShortcut, .shiftCommand)
        imageTextSearch = read(Bool.self, .imageTextSearch, false)
        keepPinsPastExpiry = read(Bool.self, .keepPinsPastExpiry, false)
        clearHistoryOnSessionLock = read(Bool.self, .clearHistoryOnSessionLock, false)
        retentionDays = min(30, max(1, read(Int.self, .retentionDays, 7)))
        maximumEntries = min(1_000, max(1, read(Int.self, .maximumEntries, 300)))
        clearClipboardAfterSeconds = min(3_600, max(0, read(Int.self, .clearClipboardAfterSeconds, 45)))
        if values.contains(.excludedBundleIDs) {
            do {
                var list = try values.nestedUnkeyedContainer(forKey: .excludedBundleIDs)
                while !list.isAtEnd {
                    if let identifier = try? list.decode(String.self) { excludedBundleIDs.insert(identifier) }
                    else { _ = try list.decode(DiscardedPreference.self); recoveryWarnings.append("excludedBundleIDs") }
                }
            } catch { recoveryWarnings.append("excludedBundleIDs") }
        }
        storageMode = read(StorageMode.self, .storageMode, .memory)
        persistPinnedOnly = read(Bool.self, .persistPinnedOnly, false)
        customFolderPath = try? values.decodeIfPresent(String.self, forKey: .customFolderPath)
        if !recoveryWarnings.isEmpty { captureEnabled = false }
    }
}

private struct DiscardedPreference: Decodable {
    init(from decoder: Decoder) throws {
        if var list = try? decoder.unkeyedContainer() {
            while !list.isAtEnd { _ = try list.decode(DiscardedPreference.self) }
        } else if let dictionary = try? decoder.container(keyedBy: Key.self) {
            for key in dictionary.allKeys { _ = try dictionary.decode(DiscardedPreference.self, forKey: key) }
        } else { _ = try decoder.singleValueContainer() }
    }
    private struct Key: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
}
