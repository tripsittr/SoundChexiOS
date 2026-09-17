import SwiftUI

/// Boxes the profiles array so `.sheet(item:)`, which needs an Identifiable, can
/// present it.
struct ProfileList: Identifiable {
    let id = UUID()
    let profiles: [Profile]
}

/// Choose which profile to sign in as, entering a PIN if that profile is locked.
struct ProfilePickerView: View {
    let profiles: [Profile]
    let onPick: (Profile, String?) async -> Void

    @State private var pinFor: Profile?
    @State private var pin = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List(profiles) { profile in
                Button {
                    if profile.requiresPin {
                        pinFor = profile
                    } else {
                        pick(profile, pin: nil)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).foregroundStyle(SoundChexTheme.ink100)
                            if profile.isKids {
                                Text("Kids").font(.caption).foregroundStyle(SoundChexTheme.ink500)
                            }
                        }
                        Spacer()
                        if profile.requiresPin {
                            Image(systemName: "lock.fill").foregroundStyle(SoundChexTheme.ink500)
                        }
                    }
                }
                .disabled(isWorking)
            }
            .navigationTitle("Choose a profile")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Enter PIN", isPresented: pinAlertBinding, presenting: pinFor) { profile in
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                Button("Sign in") { pick(profile, pin: pin) }
                Button("Cancel", role: .cancel) { pin = "" }
            }
        }
    }

    private var pinAlertBinding: Binding<Bool> {
        Binding(get: { pinFor != nil }, set: { if !$0 { pinFor = nil } })
    }

    private func pick(_ profile: Profile, pin: String?) {
        isWorking = true
        Task {
            await onPick(profile, pin)
            isWorking = false
        }
    }
}
