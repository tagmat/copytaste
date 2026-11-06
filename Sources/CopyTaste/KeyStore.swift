import Foundation
import Security
import CryptoKit
import LocalAuthentication

enum KeyStoreError: Error, LocalizedError {
    case status(OSStatus), missing, invalid
    var errorDescription: String? {
        switch self {
        case .status(let code): "Keychain is unavailable (\(code)). Unlock your login keychain and try again."
        case .missing: "The vault key is missing. Restore the original keychain; the saved vault has not been changed."
        case .invalid: "The saved vault key is invalid. The vault has not been changed."
        }
    }
}

struct KeyStore {
    private var usesDataProtection: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CopyTasteDataProtectionKeychain") as? Bool == true
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "net.tagmat.copytaste.vault",
         kSecAttrAccount as String: "encryption-key-v1",
         kSecAttrSynchronizable as String: false]
    }

    func load(allowCreation: Bool, context: LAContext? = nil) throws -> SymmetricKey {
        var request = query
        if usesDataProtection { request[kSecUseDataProtectionKeychain as String] = true }
        if let context { request[kSecUseAuthenticationContext as String] = context }
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else { throw KeyStoreError.invalid }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw KeyStoreError.status(status) }
        var legacyKey: SymmetricKey?
        if usesDataProtection {
            var legacy = request
            legacy[kSecUseDataProtectionKeychain as String] = false
            var legacyData: CFTypeRef?
            let legacyStatus = SecItemCopyMatching(legacy as CFDictionary, &legacyData)
            if legacyStatus == errSecSuccess {
                guard let data = legacyData as? Data, data.count == 32 else { throw KeyStoreError.invalid }
                legacyKey = SymmetricKey(data: data)
            } else if legacyStatus != errSecItemNotFound { throw KeyStoreError.status(legacyStatus) }
        }
        guard allowCreation || legacyKey != nil else { throw KeyStoreError.missing }
        let key = legacyKey ?? SymmetricKey(size: .bits256)
        var item = query
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        if usesDataProtection {
            item[kSecUseDataProtectionKeychain as String] = true
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
                throw error?.takeRetainedValue() ?? KeyStoreError.invalid as Error
            }
            item[kSecAttrAccessControl as String] = control
            if let context { item[kSecUseAuthenticationContext as String] = context }
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        item[kSecAttrLabel as String] = "CopyTaste encrypted history"
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeyStoreError.status(addStatus) }
        if legacyKey != nil {
            // Remove the unbound legacy copy only after the protected item can be read.
            var verified: CFTypeRef?
            let verifiedStatus = SecItemCopyMatching(request as CFDictionary, &verified)
            guard verifiedStatus == errSecSuccess, let data = verified as? Data,
                  data == key.withUnsafeBytes({ Data($0) }) else { throw KeyStoreError.status(verifiedStatus) }
            var legacyQuery = query
            legacyQuery[kSecUseDataProtectionKeychain as String] = false
            let removed = SecItemDelete(legacyQuery as CFDictionary)
            guard removed == errSecSuccess || removed == errSecItemNotFound else { throw KeyStoreError.status(removed) }
        }
        return key
    }
}
