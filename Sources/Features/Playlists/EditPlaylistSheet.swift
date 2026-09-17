import SwiftUI
import PhotosUI

/// Create or edit a playlist: name, description, and a cover image. When
/// `playlist` is nil it creates; otherwise it edits that one. `onSaved` fires
/// after a successful save so the list behind refreshes.
struct EditPlaylistSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist?
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var saving = false
    @State private var error: String?

    private var isEditing: Bool { playlist != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            coverPreview
                        }
                        Spacer()
                    }
                    .listRowBackground(SoundChexTheme.base900)
                }

                Section("Name") {
                    TextField("Playlist name", text: $name)
                        .listRowBackground(SoundChexTheme.base800)
                }
                Section("Description") {
                    TextField("Optional", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                        .listRowBackground(SoundChexTheme.base800)
                }

                if let error {
                    Text(error).foregroundStyle(SoundChexTheme.errorPink)
                        .listRowBackground(SoundChexTheme.base900)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            .navigationTitle(isEditing ? "Edit playlist" : "New playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = playlist?.name ?? ""
                description = playlist?.description ?? ""
            }
            .onChange(of: pickedItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                    }
                }
            }
        }
    }

    private var coverPreview: some View {
        Group {
            if let pickedImage {
                Image(uiImage: pickedImage).resizable().scaledToFill()
            } else {
                PlaylistCover(artworkURL: playlist?.artworkURL, mosaic: [])
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(.rect(cornerRadius: SoundChexTheme.radiusLargeArt))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(SoundChexTheme.accent, in: .circle)
                .padding(6)
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }

        guard let api = session.api else { error = "Not connected."; return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let desc = description.trimmingCharacters(in: .whitespaces)

        do {
            let id: Int
            if let playlist {
                _ = try await api.updatePlaylist(playlist.id, name: trimmedName,
                                                 description: desc.isEmpty ? nil : desc)
                id = playlist.id
            } else {
                let created = try await api.createPlaylist(name: trimmedName,
                                                           description: desc.isEmpty ? nil : desc)
                id = created.id
            }

            // Upload a new cover if one was picked.
            if let pickedImage, let jpeg = pickedImage.jpegData(compressionQuality: 0.85) {
                _ = try await api.uploadPlaylistCover(id, jpeg: jpeg)
            }

            onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIClient.APIError)?.errorDescription ?? "Could not save."
        }
    }
}
