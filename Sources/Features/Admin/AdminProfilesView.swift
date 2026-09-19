// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Manage the account's profiles (household members) — the admin profile
/// management. List, create, edit (name/colour/kids/rating/PIN), delete.
struct AdminProfilesView: View {
    @Environment(Session.self) private var session
    @Environment(ThemeStore.self) private var theme
    @State private var profiles: [AdminProfile] = []
    @State private var ratings: [String] = []
    @State private var loading = true
    @State private var editing: AdminProfile?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(profiles) { profile in
                Button {
                    editing = profile
                } label: {
                    HStack(spacing: 12) {
                        AvatarDot(color: profile.color, initial: profile.initial ?? "?")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).foregroundStyle(SoundChexTheme.ink100)
                            let tags = [
                                profile.isOwner ? "Owner" : nil,
                                profile.isKids ? "Kids" : nil,
                                profile.maxRating.map { "≤ \($0)" },
                                profile.requiresPin ? "PIN" : nil,
                            ].compactMap { $0 }
                            if !tags.isEmpty {
                                Text(tags.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(SoundChexTheme.ink500)
                            }
                        }
                        Spacer()
                    }
                }
                .listRowBackground(SoundChexTheme.base900)
                .swipeActions {
                    if !profile.isOwner {
                        Button(role: .destructive) {
                            delete(profile)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(SoundChexTheme.base900)
        .overlay { if loading { ProgressView().tint(SoundChexTheme.accent) } }
        .navigationTitle("Profiles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { profile in
            AdminProfileEditView(profile: profile, ratings: ratings) { await load() }
                .soundchexTheme(theme)
        }
        .sheet(isPresented: $creating) {
            AdminProfileEditView(profile: nil, ratings: ratings) { await load() }
                .soundchexTheme(theme)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        if let response = try? await session.api?.adminProfiles() {
            profiles = response.profiles
            ratings = response.ratings
        }
        loading = false
    }

    private func delete(_ profile: AdminProfile) {
        Task {
            try? await session.api?.deleteProfile(profile.id)
            await load()
        }
    }
}

/// A small coloured avatar dot with an initial, for the profile list.
struct AvatarDot: View {
    let color: String?
    let initial: String

    var body: some View {
        Circle()
            .fill((color.flatMap(Color.init(hex:))) ?? SoundChexTheme.accent)
            .frame(width: 36, height: 36)
            .overlay(Text(initial).font(.subheadline.weight(.semibold)).foregroundStyle(.white))
    }
}

/// Create or edit one profile.
struct AdminProfileEditView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let profile: AdminProfile?
    let ratings: [String]
    var onDone: () async -> Void

    @State private var name = ""
    @State private var isKids = false
    @State private var maxRating: String = ""
    @State private var pin = ""
    @State private var saving = false
    @State private var error: String?

    private var isNew: Bool { profile == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Name", text: $name) }
                Section {
                    Toggle("Kids profile", isOn: $isKids)
                    Picker("Max rating", selection: $maxRating) {
                        Text("No limit").tag("")
                        ForEach(ratings, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("PIN") {
                    SecureField(profile?.requiresPin == true ? "Change PIN (blank to keep)" : "Set a PIN (optional)",
                                text: $pin)
                        .keyboardType(.numberPad)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            .navigationTitle(isNew ? "New profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = profile?.name ?? ""
            isKids = profile?.isKids ?? false
            maxRating = profile?.maxRating ?? ""
        }
    }

    private func save() {
        saving = true
        let ratingValue = maxRating.isEmpty ? nil : maxRating
        // Only send the PIN when the user typed one (blank keeps the existing).
        let pinValue: String? = pin.isEmpty ? nil : pin
        Task {
            do {
                if let profile {
                    _ = try await session.api?.updateProfile(
                        profile.id, name: name, color: profile.color, isKids: isKids,
                        maxRating: ratingValue, pin: pinValue)
                } else {
                    _ = try await session.api?.createProfile(
                        name: name, color: nil, isKids: isKids,
                        maxRating: ratingValue, pin: pinValue)
                }
                await onDone()
                dismiss()
            } catch {
                self.error = (error as? APIClient.APIError)?.errorDescription ?? "Couldn't save."
            }
            saving = false
        }
    }
}
