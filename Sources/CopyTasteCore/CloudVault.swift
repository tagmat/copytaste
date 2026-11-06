import Foundation
import CryptoKit
import CommonCrypto

public struct SyncState: Codable, Equatable, Sendable {
    public var snapshot: VaultSnapshot
    public var deletions: [String: Date] = [:]
    public var deletedCollections: [UUID: Date] = [:]
    public var clearedAt: Date?
    public var generation: UUID?

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

    public mutating func compactDeletionLog() {
        if let clearedAt { deletions = deletions.filter { $0.value > clearedAt } }
    }

    // Automatic retention is a local view, not a user deletion in the shared library.
    public mutating func applyLocalChanges(from old: VaultSnapshot, to new: VaultSnapshot,
                                          explicitDeletion: Bool = false, clearAll: Bool = false,
                                          now: Date = Date()) {
        var delta = SyncState(snapshot: new)
        delta.generation = generation
        if clearAll { delta.clearedAt = now }
        else if explicitDeletion {
            let remaining = Set(new.entries.map(\.fingerprint))
            for entry in old.entries where !remaining.contains(entry.fingerprint) {
                delta.deletions[entry.fingerprint] = now
            }
        }
        let folders = Set(new.collections.map(\.id))
        for folder in old.collections where !folders.contains(folder.id) { delta.deletedCollections[folder.id] = now }
        self = merging(delta)
        var limits = Preferences()
        limits.maximumEntries = 1_000; limits.retentionDays = 30; limits.keepPinsPastExpiry = true
        snapshot = History.pruned(snapshot, preferences: limits, now: now)
        compactDeletionLog()
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
                if entry.modifiedAt > prior.modifiedAt || (entry.modifiedAt == prior.modifiedAt && prior.mergeOrder.lexicographicallyPrecedes(entry.mergeOrder)) {
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
        case .tooManyDeletes: "The sync deletion log needs maintenance. Open advanced settings and choose Compact Sync History. Pending changes stay in memory."
        case .collectionLimit: "The shared history exceeds 30 folders. Remove unused folders on a Mac and sync again. The existing file was not replaced."
        }
    }
}

public struct CloudVault: Sendable {
    public let url: URL
    private let salt: Data
    private let key: SymmetricKey
    private let passphraseBytes: Data
    private let legacyPassphrases: [Data]
    private let keys = DerivedKeyCache()
    private static let magic = Data("CTSYNC02".utf8)
    private static let legacyMagic = Data("CTSYNC01".utf8)
    private static let maximumFileBytes = 48 * 1_024 * 1_024

    public static func iCloudURL() throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { throw CloudVaultError.unavailable }
        return root.appendingPathComponent("CopyTaste", isDirectory: true).appendingPathComponent("history.copytaste")
    }

    public static func connect(url: URL, passphrase: String, createIfMissing: Bool = true) throws -> CloudVault {
        let normalized = passphrase.precomposedStringWithCanonicalMapping
        guard normalized.count >= 16, normalized.utf8.count <= 1_024 else { throw CloudVaultError.weakPassphrase }
        try privateDirectory(url.deletingLastPathComponent())
        try requireDownloaded(url)
        var connected: CloudVault?
        try coordinated(url) { location in
            try requireDownloaded(location)
            let salt: Data
            if FileManager.default.fileExists(atPath: location.path) {
                let file = try readBounded(location)
                guard file.count > 52, (file.starts(with: magic) || file.starts(with: legacyMagic)) else { throw CloudVaultError.invalidFile }
                salt = file.subdata(in: 8..<24)
            } else {
                guard createIfMissing else { throw CloudVaultError.missingVault }
                salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
            }
            let bytes = Data(normalized.utf8)
            let legacy = [Data(passphrase.utf8), Data(passphrase.decomposedStringWithCanonicalMapping.utf8)]
            let vault = CloudVault(url: url, salt: salt, key: try derive(bytes, salt: salt), passphraseBytes: bytes, legacyPassphrases: legacy)
            if FileManager.default.fileExists(atPath: location.path) {
                _ = try vault.decode(readBounded(location))
            } else { try Self.write(vault.encode(SyncState()), to: location) }
            connected = vault
        }
        guard let connected else { throw CloudVaultError.unavailable }
        return connected
    }

    // NSFileCoordinator serialises local access. Unresolved iCloud versions are merged before writing.
    public func exchange(_ local: SyncState, preferences: Preferences, allowImport: Bool = false) throws -> SyncState {
        var result = local
        try Self.requireDownloaded(url)
        try Self.coordinated(url) { location in
            try Self.requireDownloaded(location)
            guard FileManager.default.fileExists(atPath: location.path) else { throw CloudVaultError.missingVault }
            let remoteBytes = try Self.readBounded(location)
            let remote = try decode(remoteBytes)
            let opening = local.generation == nil && local.snapshot == VaultSnapshot() && local.deletions.isEmpty && local.deletedCollections.isEmpty && local.clearedAt == nil
            if local.generation != remote.generation, !(opening || allowImport) {
                throw CloudVaultError.changedVault
            }
            var merged = local.merging(remote)
            merged.generation = remote.generation
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: location) ?? []
            for conflict in conflicts {
                let state = try decode(Self.readBounded(conflict.url))
                guard state.generation == remote.generation else { throw CloudVaultError.changedVault }
                merged = merged.merging(state)
            }
            guard merged.snapshot.collections.count <= 30 else { throw CloudVaultError.collectionLimit }
            merged.snapshot = Self.canonicalSnapshot(merged.snapshot)
            merged.compactDeletionLog()
            guard merged.deletionLogWithinLimits else { throw CloudVaultError.tooManyDeletes }
            // Adopt the file's salt so independently initialised peers converge on one KDF key.
            let remoteSalt = remoteBytes.subdata(in: 8..<24)
            if merged != remote || !conflicts.isEmpty || !remoteBytes.starts(with: Self.magic) {
                try Self.write(encode(merged, fileSalt: remoteSalt), to: location)
            }
            for conflict in conflicts { conflict.isResolved = true; try? conflict.remove() }
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

    public static func visibleSnapshot(_ snapshot: VaultSnapshot, preferences: Preferences) -> VaultSnapshot {
        var visible = snapshot
        let policy = CapturePolicy(excludedBundleIDs: preferences.excludedBundleIDs)
        visible.entries.removeAll { policy.isExcluded($0.sourceBundleID) }
        return History.pruned(visible, preferences: preferences)
    }

    public func readState() throws -> SyncState {
        var state: SyncState?
        try Self.coordinated(url) { location in
            try Self.requireDownloaded(location)
            state = try decode(Self.readBounded(location))
        }
        guard let state else { throw CloudVaultError.unavailable }
        return state
    }

    private static func canonicalSnapshot(_ snapshot: VaultSnapshot) -> VaultSnapshot {
        var safe = snapshot
        let policy = CapturePolicy()
        safe.entries.removeAll { entry in
            policy.isExcluded(entry.sourceBundleID) || entry.sourceBundleID.isEmpty ||
            (entry.text.map { policy.rejection(forText: $0, manual: entry.sourceBundleID == CapturePolicy.ownBundleID) != nil } ?? false) ||
            (entry.title.map { $0.utf8.count > 512 || CapturePolicy.containsSecret($0, includeAmbiguous: false) } ?? false) ||
            (entry.kind == .text || entry.kind == .link) && entry.text == nil ||
            entry.kind == .image && entry.imageData == nil ||
            (entry.kind == .file && (entry.fileData == nil || entry.fileName == nil ||
                policy.rejection(forFile: entry.fileData ?? Data(), name: entry.fileName ?? "") != nil)) ||
            entry.byteCount > (entry.kind == .file ? CapturePolicy.maxFileBytes : (entry.kind == .image ? CapturePolicy.maxImageBytes : CapturePolicy.maxTextBytes))
        }
        var limits = Preferences()
        limits.maximumEntries = 1_000
        limits.retentionDays = 30
        limits.keepPinsPastExpiry = true
        return History.pruned(safe, preferences: limits)
    }

    // A new generation replaces deletion evidence only after archiving the encrypted state.
    // Connected stale clients must reopen; their old snapshot cannot restore deleted pins.
    public func compact(_ local: SyncState) throws -> SyncState {
        var result = local
        try Self.coordinated(url) { location in
            try Self.requireDownloaded(location)
            let bytes = try Self.readBounded(location)
            let remote = try decode(bytes)
            guard local.generation == remote.generation else { throw CloudVaultError.changedVault }
            var merged = local.merging(remote)
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: location) ?? []
            for conflict in conflicts {
                let state = try decode(Self.readBounded(conflict.url))
                guard state.generation == remote.generation else { throw CloudVaultError.changedVault }
                merged = merged.merging(state)
            }
            guard merged.snapshot.collections.count <= 30 else { throw CloudVaultError.collectionLimit }
            let backup = location.deletingLastPathComponent().appendingPathComponent("history-before-compaction-" + UUID().uuidString + ".copytaste")
            try Self.write(encode(merged, fileSalt: bytes.subdata(in: 8..<24)), to: backup)
            var fresh = SyncState(snapshot: Self.canonicalSnapshot(merged.snapshot))
            fresh.generation = UUID()
            try Self.write(encode(fresh, fileSalt: bytes.subdata(in: 8..<24)), to: location)
            for conflict in conflicts { conflict.isResolved = true; try? conflict.remove() }
            result = fresh
        }
        return result
    }

    private func encode(_ state: SyncState, fileSalt: Data? = nil) throws -> Data {
        let plaintext = try JSONEncoder().encode(state)
        guard plaintext.count < Self.maximumFileBytes - 64 else { throw VaultError.oversized }
        let salt = fileSalt ?? salt
        var header = Self.magic
        header.append(salt)
        let sealed = try AES.GCM.seal(plaintext, using: derivedKey(salt), authenticating: header)
        guard let box = sealed.combined else { throw CloudVaultError.invalidFile }
        header.append(box)
        try Task.checkCancellation()
        return header
    }

    private func derivedKey(_ fileSalt: Data) throws -> SymmetricKey {
        if fileSalt == salt { return key }
        if let cached = keys.get(fileSalt) { return cached }
        let derived = try Self.derive(passphraseBytes, salt: fileSalt)
        keys.set(derived, for: fileSalt)
        return derived
    }

    private func decode(_ bytes: Data) throws -> SyncState {
        guard bytes.count > 52, bytes.starts(with: Self.magic) || bytes.starts(with: Self.legacyMagic) else { throw CloudVaultError.invalidFile }
        do {
            let fileSalt = bytes.subdata(in: 8..<24)
            let box = try AES.GCM.SealedBox(combined: bytes.dropFirst(24))
            var plaintext = try? AES.GCM.open(box, using: derivedKey(fileSalt), authenticating: bytes.prefix(24))
            if plaintext == nil, bytes.starts(with: Self.legacyMagic) {
                for password in legacyPassphrases where password != passphraseBytes {
                    if let opened = try? AES.GCM.open(box, using: Self.derive(password, salt: fileSalt), authenticating: bytes.prefix(24)) {
                        plaintext = opened
                        break
                    }
                }
            }
            guard let plaintext else { throw CloudVaultError.invalidFile }
            let state = try JSONDecoder().decode(SyncState.self, from: plaintext)
            guard state.snapshot.version == 1, state.snapshot.entries.count <= 1_000,
                  state.snapshot.collections.count <= 30,
                  state.deletions.count <= 200_000, state.deletedCollections.count <= 20_000 else { throw CloudVaultError.invalidContent }
            return state
        } catch let error as CloudVaultError { throw error }
        catch { throw CloudVaultError.invalidFile }
    }

    private static func readBounded(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CloudVaultError.missingVault }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.intValue <= maximumFileBytes else { throw VaultError.oversized }
        let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard attributes.isSymbolicLink != true, attributes.isRegularFile == true else { throw VaultError.unsafePath }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumFileBytes else { throw VaultError.oversized }
        return data
    }

    private static func privateDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw VaultError.unsafePath }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try Task.checkCancellation()
        try privateDirectory(url.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: url.path), try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw VaultError.unsafePath }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // iCloud is the transport; excluding this file from its provider would disable sync.
    }

    private static func derive(_ password: Data, salt: Data) throws -> SymmetricKey {
        guard !password.isEmpty, salt.count == 16 else { throw CloudVaultError.invalidFile }
        var output = [UInt8](repeating: 0, count: 32)
        defer { _ = output.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let status = password.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                guard let base = pass.baseAddress, let saltBase = saltBytes.baseAddress else { return Int32(kCCParamError) }
                return CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), base.assumingMemoryBound(to: CChar.self), password.count,
                    saltBase.assumingMemoryBound(to: UInt8.self), salt.count,
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

private final class DerivedKeyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data: SymmetricKey] = [:]
    func get(_ salt: Data) -> SymmetricKey? { lock.withLock { values[salt] } }
    func set(_ key: SymmetricKey, for salt: Data) {
        lock.withLock {
            if values.count >= 8 { values.removeAll() }
            values[salt] = key
        }
    }
}

private extension ClipEntry {
    var mergeOrder: [String] {
        [id.uuidString, String(createdAt.timeIntervalSinceReferenceDate), isPinned ? "1" : "0",
         collectionID?.uuidString ?? "", title ?? "", sourceBundleID, sourceName]
    }
}
