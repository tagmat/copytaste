import Foundation
import CryptoKit
import CommonCrypto

public struct SyncState: Codable, Equatable, Sendable {
    public var snapshot: VaultSnapshot
    public var deletions: [String: Date] = [:]
    public var deletedCollections: [UUID: Date] = [:]
    public var clearedAt: Date?

    public init(snapshot: VaultSnapshot = VaultSnapshot()) { self.snapshot = snapshot }

    public var deletionLogWithinLimits: Bool {
        deletions.count <= 20_000 && deletedCollections.count <= 2_000
    }

    public mutating func recordChanges(from old: VaultSnapshot, to new: VaultSnapshot, now: Date = Date()) {
        let remaining = Set(new.entries.map(\.fingerprint))
        for entry in old.entries where !remaining.contains(entry.fingerprint) { deletions[entry.fingerprint] = now }
        let collections = Set(new.collections.map(\.id))
        for collection in old.collections where !collections.contains(collection.id) { deletedCollections[collection.id] = now }
        snapshot = new
    }

    public func merging(_ other: SyncState) -> SyncState {
        var result = self
        result.deletions.merge(other.deletions, uniquingKeysWith: max)
        result.deletedCollections.merge(other.deletedCollections, uniquingKeysWith: max)
        result.clearedAt = [clearedAt, other.clearedAt].compactMap { $0 }.max()
        var entries: [String: ClipEntry] = [:]
        for entry in snapshot.entries + other.snapshot.entries {
            guard entry.createdAt > (result.clearedAt ?? .distantPast),
                  entry.createdAt > (result.deletions[entry.fingerprint] ?? .distantPast) else { continue }
            if let prior = entries[entry.fingerprint] {
                if entry.modifiedAt > prior.modifiedAt || (entry.modifiedAt == prior.modifiedAt && entry.id.uuidString > prior.id.uuidString) {
                    entries[entry.fingerprint] = entry
                }
            } else { entries[entry.fingerprint] = entry }
        }
        var collections: [UUID: ClipCollection] = [:]
        for collection in snapshot.collections + other.snapshot.collections where result.deletedCollections[collection.id] == nil {
            if let prior = collections[collection.id] {
                let incoming = collection.modifiedAt ?? .distantPast
                let previous = prior.modifiedAt ?? .distantPast
                if incoming < previous || (incoming == previous && !prior.name.utf8.lexicographicallyPrecedes(collection.name.utf8)) {
                    continue
                }
            }
            collections[collection.id] = collection
        }
        result.snapshot = VaultSnapshot(entries: entries.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt
        }, collections: collections.values.sorted { $0.id.uuidString < $1.id.uuidString })
        for index in result.snapshot.entries.indices {
            if let id = result.snapshot.entries[index].collectionID, collections[id] == nil {
                result.snapshot.entries[index].collectionID = nil
            }
        }
        return result
    }
}

public enum CloudVaultError: Error, LocalizedError {
    case unavailable, downloading, missingVault, weakPassphrase, invalidFile, changedVault, invalidContent, tooManyDeletes, collectionLimit
    public var errorDescription: String? {
        switch self {
        case .unavailable: "iCloud Drive is unavailable. Sign in to iCloud and enable iCloud Drive in System Settings."
        case .downloading: "iCloud Drive is downloading the encrypted vault. Try again when it is available."
        case .missingVault: "The encrypted vault is missing. Restore it in iCloud Drive before trying again."
        case .weakPassphrase: "Use a sync passphrase of at least 16 characters (up to 1,024 UTF-8 bytes). Keep it safe; it cannot be recovered."
        case .invalidFile: "The sync vault is invalid or the passphrase is incorrect. The file was not replaced."
        case .changedVault: "The sync vault was replaced with a different vault. Lock and reopen with its passphrase."
        case .invalidContent: "The sync vault contains unsupported data. The file was not replaced."
        case .tooManyDeletes: "The sync deletion log is full. Capture is paused; create a new sync vault before continuing."
        case .collectionLimit: "The shared history exceeds 30 folders. Remove unused folders on a Mac and sync again. The existing file was not replaced."
        }
    }
}

public struct CloudVault: Sendable {
    public let url: URL
    private let salt: Data
    private let key: SymmetricKey
    private let passphraseBytes: Data
    private static let magic = Data("CTSYNC01".utf8)
    private static let maximumFileBytes = 48 * 1_024 * 1_024

    public static func iCloudURL() throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { throw CloudVaultError.unavailable }
        return root.appendingPathComponent("CopyTaste", isDirectory: true).appendingPathComponent("history.copytaste")
    }

    public static func connect(url: URL, passphrase: String, createIfMissing: Bool = true) throws -> CloudVault {
        guard passphrase.count >= 16, passphrase.utf8.count <= 1_024 else { throw CloudVaultError.weakPassphrase }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try requireDownloaded(url)
        var connected: CloudVault?
        try coordinated(url) { location in
            try requireDownloaded(location)
            let salt: Data
            if FileManager.default.fileExists(atPath: location.path) {
                let file = try readBounded(location)
                guard file.count > 52, file.starts(with: magic) else { throw CloudVaultError.invalidFile }
                salt = file.subdata(in: 8..<24)
            } else {
                guard createIfMissing else { throw CloudVaultError.missingVault }
                salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
            }
            let bytes = Data(passphrase.utf8)
            let vault = CloudVault(url: url, salt: salt, key: try derive(bytes, salt: salt), passphraseBytes: bytes)
            if FileManager.default.fileExists(atPath: location.path) {
                _ = try vault.decode(readBounded(location))
            } else { try vault.encode(SyncState()).write(to: location, options: .atomic) }
            connected = vault
        }
        guard let connected else { throw CloudVaultError.unavailable }
        return connected
    }

    // NSFileCoordinator serialises local access. Unresolved iCloud versions are merged before writing.
    public func exchange(_ local: SyncState, preferences: Preferences) throws -> SyncState {
        var result = local
        try Self.requireDownloaded(url)
        try Self.coordinated(url) { location in
            try Self.requireDownloaded(location)
            guard FileManager.default.fileExists(atPath: location.path) else { throw CloudVaultError.missingVault }
            let remote = try decode(Self.readBounded(location))
            var merged = local.merging(remote)
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: location) ?? []
            for conflict in conflicts { merged = merged.merging(try decode(Self.readBounded(conflict.url))) }
            guard merged.snapshot.collections.count <= 30 else { throw CloudVaultError.collectionLimit }
            var safe = merged.snapshot
            let policy = CapturePolicy(excludedBundleIDs: preferences.excludedBundleIDs)
            safe.entries.removeAll { entry in
                policy.isExcluded(entry.sourceBundleID) || entry.sourceBundleID.isEmpty ||
                (entry.text.map { policy.rejection(forText: $0) != nil } ?? false) ||
                (entry.title.map { $0.utf8.count > 512 || CapturePolicy.containsSecret($0) } ?? false) ||
                (entry.kind == .file && (entry.fileData == nil || entry.fileName == nil ||
                    policy.rejection(forFile: entry.fileData ?? Data(), name: entry.fileName ?? "") != nil)) ||
                entry.byteCount > (entry.kind == .file ? CapturePolicy.maxFileBytes : (entry.kind == .image ? CapturePolicy.maxImageBytes : CapturePolicy.maxTextBytes))
            }
            let pruned = History.pruned(safe, preferences: preferences)
            merged.recordChanges(from: merged.snapshot, to: pruned)
            guard merged.deletionLogWithinLimits else { throw CloudVaultError.tooManyDeletes }
            if merged != remote || !conflicts.isEmpty { try encode(merged).write(to: location, options: .atomic) }
            for conflict in conflicts { conflict.isResolved = true }
            result = merged
        }
        return result
    }

    private static func requireDownloaded(_ url: URL) throws {
        let fileManager = FileManager.default
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        let waitingForDownload = values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus == .notDownloaded
        if waitingForDownload || (!fileManager.fileExists(atPath: url.path) && fileManager.fileExists(atPath: placeholder.path)) {
            try fileManager.startDownloadingUbiquitousItem(at: url)
            throw CloudVaultError.downloading
        }
    }

    private func encode(_ state: SyncState) throws -> Data {
        let plaintext = try JSONEncoder().encode(state)
        guard plaintext.count < Self.maximumFileBytes - 64 else { throw VaultError.oversized }
        var header = Self.magic
        header.append(salt)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let box = sealed.combined else { throw CloudVaultError.invalidFile }
        header.append(box)
        return header
    }

    private func decode(_ bytes: Data) throws -> SyncState {
        guard bytes.count > 52, bytes.starts(with: Self.magic) else { throw CloudVaultError.invalidFile }
        do {
            let fileSalt = bytes.subdata(in: 8..<24)
            // Two Macs may independently initialise a vault before either receives the other file.
            // The same phrase can open both salts; preserve and merge both encrypted versions.
            let fileKey = fileSalt == salt ? key : try Self.derive(passphraseBytes, salt: fileSalt)
            let box = try AES.GCM.SealedBox(combined: bytes.dropFirst(24))
            let plain = try AES.GCM.open(box, using: fileKey, authenticating: bytes.prefix(24))
            let state = try JSONDecoder().decode(SyncState.self, from: plain)
            guard state.snapshot.version == 1, state.snapshot.entries.count <= 1_000,
                  state.snapshot.collections.count <= 30,
                  state.deletionLogWithinLimits else { throw CloudVaultError.invalidContent }
            return state
        } catch let error as CloudVaultError { throw error }
        catch { throw CloudVaultError.invalidFile }
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.intValue <= maximumFileBytes else { throw VaultError.oversized }
        let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard attributes.isSymbolicLink != true, attributes.isRegularFile == true else { throw VaultError.unsafePath }
        return try Data(contentsOf: url)
    }

    private static func derive(_ password: Data, salt: Data) throws -> SymmetricKey {
        var output = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress!.assumingMemoryBound(to: CChar.self), password.count,
                    saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &output, output.count)
            }
        }
        guard status == kCCSuccess else { throw CloudVaultError.invalidFile }
        return SymmetricKey(data: output)
    }

    private static func coordinated(_ url: URL, body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { location in
            do { try body(location) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}
