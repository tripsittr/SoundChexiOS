import SwiftUI

/// Edit a media item's core fields and its type metadata — the admin item edit.
/// Reached from an item's ⋯ menu when the profile is an admin.
struct AdminItemEditView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let itemID: Int

    @State private var item: AdminItem?
    @State private var title = ""
    @State private var rating = ""
    @State private var notes = ""
    @State private var meta: [String: String] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    ProgressView()
                } else {
                    Section("Title") {
                        TextField("Title", text: $title)
                    }
                    if !metaFields.isEmpty {
                        Section("Details") {
                            ForEach(metaFields, id: \.key) { field in
                                LabeledContent(field.label) {
                                    TextField(field.label, text: binding(for: field.key))
                                        .multilineTextAlignment(.trailing)
                                        .keyboardType(field.numeric ? .numberPad : .default)
                                }
                            }
                        }
                    }
                    Section("Rating") {
                        TextField("0–10", text: $rating).keyboardType(.decimalPad)
                    }
                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(saving || loading)
                }
            }
        }
        .task { await load() }
    }

    /// The type's editable fields, in display order.
    private var metaFields: [(key: String, label: String, numeric: Bool)] {
        guard let item else { return [] }
        switch item.type {
        case .music: return [("artist", "Artist", false), ("album", "Album", false), ("release_year", "Year", true)]
        case .movie: return [("director", "Director", false), ("release_year", "Year", true)]
        case .show: return [("episode_title", "Episode", false), ("season_number", "Season", true), ("episode_number", "Episode #", true)]
        case .book: return [("author", "Author", false), ("publisher", "Publisher", false)]
        case .unknown: return []
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { meta[key] ?? "" }, set: { meta[key] = $0 })
    }

    private func load() async {
        do {
            let loaded = try await session.api?.adminItem(itemID)
            item = loaded
            title = loaded?.title ?? ""
            rating = loaded?.userRating.map { String($0) } ?? ""
            notes = loaded?.notes ?? ""
            meta = loaded?.meta.mapValues(\.stringValue) ?? [:]
        } catch {
            self.error = (error as? APIClient.APIError)?.errorDescription ?? "Couldn't load."
        }
        loading = false
    }

    private func save() {
        saving = true
        // Rebuild the meta dict as typed values (int for numeric fields).
        var payload: [String: AnyCodableValue] = [:]
        for field in metaFields {
            let raw = (meta[field.key] ?? "").trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { payload[field.key] = .null }
            else if field.numeric, let i = Int(raw) { payload[field.key] = .int(i) }
            else { payload[field.key] = .string(raw) }
        }
        Task {
            do {
                _ = try await session.api?.updateAdminItem(
                    itemID, title: title,
                    userRating: Double(rating), notes: notes.isEmpty ? nil : notes,
                    meta: payload
                )
                dismiss()
            } catch {
                self.error = (error as? APIClient.APIError)?.errorDescription ?? "Couldn't save."
            }
            saving = false
        }
    }
}
