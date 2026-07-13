// OrthancCredentialStore.swift
// OpenDicomViewer
//
// Keychain-backed storage for optional Orthanc passwords.

import Foundation
import Security

enum OrthancCredentialStore {
    private static let service = "com.smartdicomviewer.orthanc"

    static func password(for serverAddress: String, username: String) -> String {
        let account = accountKey(serverAddress: serverAddress, username: username)
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return ""
        }
        return password
    }

    static func save(password: String, serverAddress: String, username: String) throws {
        let account = accountKey(serverAddress: serverAddress, username: username)
        let data = Data(password.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw OrthancCredentialStoreError("Could not update Orthanc password in Keychain (\(updateStatus)).")
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OrthancCredentialStoreError("Could not save Orthanc password to Keychain (\(addStatus)).")
        }
    }

    static func delete(serverAddress: String, username: String) {
        let account = accountKey(serverAddress: serverAddress, username: username)
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func accountKey(serverAddress: String, username: String) -> String {
        let server = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(server)|\(user)"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct OrthancCredentialStoreError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
