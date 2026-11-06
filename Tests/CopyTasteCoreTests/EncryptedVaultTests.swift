import XCTest
import CryptoKit
@testable import CopyTasteCore

final class EncryptedVaultTests: XCTestCase {
    private func withVault(_ body: (EncryptedVault, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(EncryptedVault(url: directory.appendingPathComponent("history.vault")), directory)
    }

    func testEncryptedRoundTripAndPrivatePermissions() throws {
        try withVault { vault, directory in
            let key = SymmetricKey(size: .bits256)
            let entry = ClipEntry(kind: .text, text: "unique-synthetic-content-8f6b", sourceName: "Fixture", sourceBundleID: "org.example.fixture")
            let snapshot = VaultSnapshot(entries: [entry], collections: [ClipCollection(name: "Private collection")])
            try vault.save(snapshot, key: key)
            XCTAssertEqual(try vault.load(key: key), snapshot)
            let bytes = try Data(contentsOf: vault.url)
            XCTAssertNil(bytes.range(of: Data("unique-synthetic-content-8f6b".utf8)))
            XCTAssertNil(bytes.range(of: Data("Private collection".utf8)))
            let fileMode = try FileManager.default.attributesOfItem(atPath: vault.url.path)[.posixPermissions] as? NSNumber
            let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(fileMode?.intValue, 0o600)
            XCTAssertEqual(directoryMode?.intValue, 0o700)
        }
    }

    func testWrongKeyAndTamperingDoNotReplaceOriginal() throws {
        try withVault { vault, _ in
            let key = SymmetricKey(size: .bits256)
            try vault.save(VaultSnapshot(), key: key)
            let original = try Data(contentsOf: vault.url)
            XCTAssertThrowsError(try vault.load(key: SymmetricKey(size: .bits256)))
            XCTAssertEqual(try Data(contentsOf: vault.url), original)
            var tampered = original
            tampered[tampered.count - 1] ^= 0x01
            try tampered.write(to: vault.url)
            XCTAssertThrowsError(try vault.load(key: key))
            XCTAssertEqual(try Data(contentsOf: vault.url), tampered)
        }
    }

    func testFreshNoncesProduceDifferentCiphertext() throws {
        try withVault { vault, _ in
            let key = SymmetricKey(size: .bits256)
            try vault.save(VaultSnapshot(), key: key)
            let first = try Data(contentsOf: vault.url)
            try vault.save(VaultSnapshot(), key: key)
            XCTAssertNotEqual(try Data(contentsOf: vault.url), first)
        }
    }

    func testUnknownVersionIsRejectedBeforeWriting() throws {
        try withVault { vault, _ in
            var snapshot = VaultSnapshot()
            snapshot.version = 99
            XCTAssertThrowsError(try vault.save(snapshot, key: SymmetricKey(size: .bits256)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.url.path))
        }
    }

    func testMissingVaultThrowsWithoutCreatingAReplacement() throws {
        try withVault { vault, _ in
            XCTAssertThrowsError(try vault.load(key: SymmetricKey(size: .bits256)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: vault.url.path))
        }
    }

    func testSymlinksAreRejectedWithoutTouchingDestination() throws {
        try withVault { vault, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("untouched")
            let sentinel = Data("fixture".utf8)
            try sentinel.write(to: destination)
            try FileManager.default.createSymbolicLink(at: vault.url, withDestinationURL: destination)
            XCTAssertThrowsError(try vault.save(VaultSnapshot(), key: SymmetricKey(size: .bits256)))
            XCTAssertThrowsError(try vault.load(key: SymmetricKey(size: .bits256)))
            XCTAssertEqual(try Data(contentsOf: destination), sentinel)
        }
    }
}
