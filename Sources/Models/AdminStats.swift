// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Who the current token belongs to, from `/api/v1/me`. `isAdmin` gates the
/// app's admin surface.
struct Identity: Decodable, Sendable {
    struct Account: Decodable, Sendable { let id: Int; let name: String; let email: String }
    struct Prof: Decodable, Sendable {
        let id: Int
        let name: String
        let isOwner: Bool
        let isAdmin: Bool
    }
    let user: Account
    let profile: Prof?
}

/// The admin dashboard figures from `/api/v1/admin/stats`.
struct AdminStats: Decodable, Sendable {
    struct Library: Decodable, Sendable {
        let music: Int
        let movie: Int
        let show: Int
        let book: Int
        let total: Int
    }
    struct TopItem: Decodable, Identifiable, Sendable {
        let id: Int
        let title: String
        let subtitle: String?
        let artwork: URL?
        let plays: Int
    }
    let library: Library
    let accounts: Int
    let profiles: Int
    let playsLast7Days: Int
    let topItems: [TopItem]
}
