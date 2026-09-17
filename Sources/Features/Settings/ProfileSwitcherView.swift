import SwiftUI

/// Switching profile.
///
/// A token is bound to one profile and minting a new one needs the password,
/// which the app deliberately does not keep. So switching re-authenticates: it
/// signs the current profile out and returns to the sign-in screen, where the
/// profile picker appears again. Explained here so it doesn't read as a bug.
struct ProfileSwitcherView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    /// Called after sign-out so the presenting settings sheet can close too.
    var onSwitched: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                SoundChexTheme.base900.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(SoundChexTheme.accent)
                    Text("Switch profile")
                        .font(.title2.bold())
                        .foregroundStyle(SoundChexTheme.ink100)
                    Text("To keep your account secure, switching profiles signs you out and asks you to sign in again — then you can pick a different profile.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SoundChexTheme.ink400)
                        .padding(.horizontal, 32)

                    Button {
                        Task {
                            await session.signOut()
                            onSwitched()
                        }
                    } label: {
                        Text("Sign out and switch")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SoundChexTheme.accent, in: .rect(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
