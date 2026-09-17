// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Security

/// The auth token store.
///
/// A bearer token is a credential, so it lives in the Keychain rather than
/// UserDefaults — it survives reinstalls off by default, is encrypted at rest,
/// and is never included in a device backup that could leak it. Keyed by server
/// URL so two servers do not share a token.
enum Keychain {
    private static let service = "net.soundchex.ios.token"

    static func token(for server: URL) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }

        return string
    }

    static func setToken(_ token: String, for server: URL) {
        // Delete any existing entry first, so this is an upsert rather than a
        // duplicate-insert failure.
        deleteToken(for: server)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
            kSecValueData as String: Data(token.utf8),
            // Available after first unlock, so a background refresh can still
            // read it, but never restored to a different device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteToken(for server: URL) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
