// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// "How long do you want to keep this?" (S-404).
///
/// Shown before a video download and nowhere else. A film is 2–10GB against a
/// song's 5MB, so an unattended video download is the one that quietly fills a
/// phone — and asking the same question about a song would be a tax on every
/// tap for no benefit.
///
/// The window means *unused* for that long: watching resets the clock, so a
/// series you are part-way through does not disappear between two episodes.
/// The footer says so, because a countdown nobody understands is a countdown
/// people work around by always choosing "Keep it".
struct RetentionPicker: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onPick: (DownloadRetention) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DownloadRetention.allCases) { option in
                        Button {
                            // Permission asked here, the first time someone
                            // actually chooses a timed download — not at
                            // launch (S-405). A prompt before the app has
                            // shown what it is for is the one people deny,
                            // and a denial cannot be re-prompted.
                            if option != .forever {
                                Task { _ = await ExpiryNotifications.requestPermission() }
                            }

                            onPick(option)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .foregroundStyle(SoundChexTheme.ink100)
                                    Text(option.hint)
                                        .font(.caption)
                                        .foregroundStyle(SoundChexTheme.ink500)
                                }

                                Spacer()

                                Image(systemName: option == .forever
                                    ? "internaldrive"
                                    : "clock")
                                    .foregroundStyle(SoundChexTheme.ink500)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(SoundChexTheme.base800)
                    }
                } header: {
                    Text("Keep this download for")
                } footer: {
                    Text("Watching it starts the clock again, so something you "
                        + "are part-way through will not disappear. When the "
                        + "time is up the file is deleted but stays listed, "
                        + "ready to download again.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
