// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// "This item is wrong, and here is why" (S-400).
///
/// Two steps, and the first one is the important one. Reporting hides the item
/// from the library until an admin clears it (S-396) — a large consequence for
/// one tap in a menu whose neighbours are "Play next" and "Add to queue". So
/// the menu entry raises a confirmation that says plainly what will happen,
/// and only a deliberate "Send for review" opens this sheet to ask why.
///
/// Presented as a sheet rather than pushed, because reporting is an aside from
/// whatever the person was doing and they should land back exactly where they
/// were.
struct SendForReviewSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem

    /// Told when the report lands, so the list behind can drop the row — the
    /// item has just left the library and the page is now showing something
    /// that is not there any more.
    var onSent: () -> Void = {}

    @State private var reason: APIClient.ReviewReason = .metadata
    @State private var note = ""
    @State private var sending = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(APIClient.ReviewReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: reason == option
                                    ? "largecircle.fill.circle"
                                    : "circle")
                                    .foregroundStyle(reason == option
                                        ? SoundChexTheme.accent
                                        : SoundChexTheme.ink500)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .foregroundStyle(SoundChexTheme.ink100)
                                    Text(option.hint)
                                        .font(.caption)
                                        .foregroundStyle(SoundChexTheme.ink500)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("What is wrong?")
                }

                Section {
                    TextField("The more specific, the faster it gets fixed.",
                              text: $note, axis: .vertical)
                        .lineLimit(3 ... 6)
                } header: {
                    Text("Anything else worth saying")
                } footer: {
                    Text("This item will be hidden from your library until "
                        + "someone has looked at it. Nothing is deleted.")
                }

                if let failure {
                    Section {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(sending)
                }
            }
            .overlay {
                if sending {
                    ProgressView().tint(SoundChexTheme.accent)
                }
            }
        }
    }

    private func send() {
        guard let api = session.api else {
            failure = "Not connected to a server."
            return
        }

        sending = true
        failure = nil

        Task {
            do {
                try await api.sendForReview(
                    itemID: item.id,
                    reason: reason,
                    // An empty box is no note, not an empty one.
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : note.trimmingCharacters(in: .whitespacesAndNewlines),
                )

                onSent()
                dismiss()
            } catch {
                AppLog.error("Send for review failed: \(error)", category: "review")
                failure = "Could not send that. Check the connection and try again."
                sending = false
            }
        }
    }
}
