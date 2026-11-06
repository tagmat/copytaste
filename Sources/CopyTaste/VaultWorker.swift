import CopyTasteCore
import CryptoKit
import Foundation

// File coordination, JSON, encryption and KDF work never run on the UI actor.
actor VaultWorker {
    func save(_ snapshot: VaultSnapshot, to url: URL, key: SymmetricKey) throws {
        try Task.checkCancellation()
        try EncryptedVault(url: url).save(snapshot, key: key)
    }

    func load(from url: URL, key: SymmetricKey) throws -> VaultSnapshot {
        try EncryptedVault(url: url).load(key: key)
    }

    func connect(url: URL, passphrase: String, create: Bool) throws -> CloudVault {
        try CloudVault.connect(url: url, passphrase: passphrase, createIfMissing: create)
    }

    func exchange(_ state: SyncState, vault: CloudVault, preferences: Preferences, allowImport: Bool = false) throws -> SyncState {
        try Task.checkCancellation()
        return try vault.exchange(state, preferences: preferences, allowImport: allowImport)
    }

    func compact(_ state: SyncState, vault: CloudVault) throws -> SyncState {
        try vault.compact(state)
    }

    func read(_ vault: CloudVault) throws -> SyncState { try vault.readState() }
}
