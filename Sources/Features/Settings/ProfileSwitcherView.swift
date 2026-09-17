import SwiftUI

/// Switch which profile is using the account — no sign-out, no password.
///
/// An account (the Laravel login) has several profiles (the people using it),
/// each with its own library, history and rating cap. Switching is just choosing
/// who is using the app now: the current token already proves the account, so
/// the server issues a fresh profile-bound token and the app swaps it in. A PIN
/// is asked only where that profile is locked.
struct ProfileSwitcherView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    /// Closes the presenting settings sheet after a successful switch.
    var onSwitched: () -> Void

    @State private var profiles: [Profile] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SoundChexTheme.base900.ignoresSafeArea()

                if let loadError {
                    ContentUnavailableView("Couldn't load profiles",
                                           systemImage: "person.slash",
                                           description: Text(loadError))
                } else if profiles.isEmpty {
                    ProgressView().tint(SoundChexTheme.accent)
                } else {
                    ProfilePickerView(
                        profiles: profiles,
                        onPick: { profile, pin in await switchTo(profile, pin: pin) }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            do { profiles = try await session.myProfiles() }
            catch { loadError = (error as? APIClient.APIError)?.errorDescription
                ?? "Could not load profiles." }
        }
    }

    private func switchTo(_ profile: Profile, pin: String?) async {
        do {
            try await session.switchProfile(to: profile, pin: pin)
            onSwitched()
        } catch {
            loadError = (error as? APIClient.APIError)?.errorDescription
                ?? "Could not switch profile."
        }
    }
}
