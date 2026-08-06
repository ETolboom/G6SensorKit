//
//  G6ShareCredentialStore.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//
//  Optional Dexcom Share upload credentials live ONLY in the iOS Keychain.
//  They are deliberately kept out of the CGM manager's rawState, which the
//  host persists in UserDefaults (unencrypted, included in device backups).
//  Pattern follows LibreLoop's LibreLoopKeychain.
//

import Foundation
import Security

public struct G6ShareCredentials: Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public enum G6ShareCredentialStoreError: Error {
    case unexpectedStatus(OSStatus)
    case malformedPayload
}

/// Keychain-backed store for optional Dexcom Share credentials.
public struct G6ShareCredentialStore {

    /// Service identifier owned by this plugin. Note that LoopKit's
    /// `credentialStoragePrefix(for:)` is unusable for durable storage — Loop
    /// returns a fresh UUID on every call — so we namespace ourselves.
    static let service = "org.nightscout.G6SensorKit.shareCredentials"

    private let account: String

    /// - Parameter transmitterID: scopes credentials to a transmitter so
    ///   replacing hardware doesn't silently reuse stale credentials.
    public init(transmitterID: String) {
        self.account = transmitterID
    }

    public func save(_ credentials: G6ShareCredentials) throws {
        // Store as "username\npassword"; usernames cannot contain a newline.
        let payload = Data("\(credentials.username)\n\(credentials.password)".utf8)

        var query = baseQuery
        query[kSecValueData as String] = payload
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(query as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [String: Any] = [kSecValueData as String: payload]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw G6ShareCredentialStoreError.unexpectedStatus(updateStatus)
            }
        default:
            throw G6ShareCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    public func load() throws -> G6ShareCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let joined = String(data: data, encoding: .utf8)
            else {
                throw G6ShareCredentialStoreError.malformedPayload
            }

            let parts = joined.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw G6ShareCredentialStoreError.malformedPayload
            }

            return G6ShareCredentials(username: String(parts[0]), password: String(parts[1]))
        case errSecItemNotFound:
            return nil
        default:
            throw G6ShareCredentialStoreError.unexpectedStatus(status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw G6ShareCredentialStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }
}
