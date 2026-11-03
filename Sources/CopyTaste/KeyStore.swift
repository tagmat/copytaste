import Foundation
import Security
import CryptoKit

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
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "net.tagmat.copytaste.vault",
         kSecAttrAccount as String: "encryption-key-v1",
         kSecAttrSynchronizable as String: false]
    }

    func load(allowCreation: Bool) throws -> SymmetricKey {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else { throw KeyStoreError.invalid }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw KeyStoreError.status(status) }
        guard allowCreation else { throw KeyStoreError.missing }
        let key = SymmetricKey(size: .bits256)
        var item = query
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "CopyTaste encrypted history"
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeyStoreError.status(addStatus) }
        return key
    }
}
