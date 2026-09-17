import SwiftUI

/// Boxes the profiles array so `.fullScreenCover(item:)`, which needs an
/// Identifiable, can present it.
struct ProfileList: Identifiable {
    let id = UUID()
    let profiles: [Profile]
}

/// The full-page profile chooser — "Who's listening?" — a grid of avatar tiles,
/// the way a streaming app opens. Replaces the earlier sheet: choosing a profile
/// is a deliberate step, not a popover.
///
/// A locked profile asks for its PIN in an alert before continuing. `onPick`
/// mints the token; `onCancel` returns to the credentials form.
struct ProfilePickerView: View {
    let profiles: [Profile]
    let onPick: (Profile, String?) async -> Void
    var onCancel: (() -> Void)?

    @State private var pinFor: Profile?
    @State private var pin = ""
    @State private var working: Profile?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 24)]

    var body: some View {
        ZStack {
            SoundChexTheme.base900.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("Who's listening?")
                    .font(.title.bold())
                    .foregroundStyle(SoundChexTheme.ink100)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(profiles) { profile in
                            tile(profile)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                if let onCancel {
                    Button("Use a different account", action: onCancel)
                        .font(.subheadline)
                        .foregroundStyle(SoundChexTheme.ink500)
                }
            }
            .padding(.vertical, 48)
        }
        .alert("Enter PIN", isPresented: pinAlertBinding, presenting: pinFor) { profile in
            SecureField("PIN", text: $pin).keyboardType(.numberPad)
            Button("Sign in") { pick(profile, pin: pin) }
            Button("Cancel", role: .cancel) { pin = "" }
        } message: { profile in
            Text("\(profile.name) is protected by a PIN.")
        }
    }

    private func tile(_ profile: Profile) -> some View {
        Button {
            if profile.requiresPin {
                pinFor = profile
            } else {
                pick(profile, pin: nil)
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    ProfileAvatar(profile: profile, size: 100)
                        .opacity(working == profile ? 0.4 : 1)
                    if working == profile {
                        ProgressView().tint(.white)
                    }
                    if profile.requiresPin {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5), in: .circle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(8)
                    }
                }
                .frame(width: 100, height: 100)

                Text(profile.name)
                    .font(.subheadline)
                    .foregroundStyle(SoundChexTheme.ink300)
                    .lineLimit(1)

                if profile.isKids {
                    Text("Kids").font(.caption2).foregroundStyle(SoundChexTheme.ink500)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
    }

    private var pinAlertBinding: Binding<Bool> {
        Binding(get: { pinFor != nil }, set: { if !$0 { pinFor = nil } })
    }

    private func pick(_ profile: Profile, pin: String?) {
        working = profile
        Task {
            await onPick(profile, pin)
            working = nil
        }
    }
}
