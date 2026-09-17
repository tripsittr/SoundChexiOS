// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The sign-in screen: server address, email, password.
///
/// One screen that both picks the server and authenticates, mirroring the merged
/// connect+login the web app arrived at. All three are required; a bad server or
/// wrong credentials show a message here rather than failing silently.
struct SignInView: View {
    @Environment(Session.self) private var session

    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    /// Once credentials verify, the account's profiles to choose from. Presenting
    /// this sheet is step two of sign-in.
    @State private var profiles: [Profile]?

    var body: some View {
        ZStack {
            SoundChexTheme.base900.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    field("Server address", text: $server,
                          prompt: "https://yourmachine.ts.net",
                          keyboard: .URL, content: .URL)

                    field("Email", text: $email,
                          prompt: "you@example.com",
                          keyboard: .emailAddress, content: .username)

                    secureField("Password", text: $password)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    signInButton

                    // Version + release name, so the build is identifiable from
                    // the very first screen.
                    Text("SoundChex \(AppRelease.display)")
                        .font(.caption2)
                        .foregroundStyle(SoundChexTheme.ink500)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(SoundChexTheme.accent)
        // The profile chooser is a full page, not a sheet — picking who is
        // listening is its own step. Covers the form until a profile is chosen
        // or the user backs out to a different account.
        .fullScreenCover(item: profilesBinding) { list in
            ProfilePickerView(
                profiles: list.profiles,
                onPick: { profile, pin in await completeSignIn(profile: profile, pin: pin) },
                onCancel: { profiles = nil }
            )
        }
    }

    /// The profiles list wrapped so `.fullScreenCover(item:)` can present it — it
    /// needs an Identifiable, so the array is boxed.
    private var profilesBinding: Binding<ProfileList?> {
        Binding(
            get: { profiles.map(ProfileList.init) },
            set: { profiles = $0?.profiles }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in to your library")
                .font(.largeTitle.bold())
                .foregroundStyle(SoundChexTheme.ink100)
            Text("The address of your SoundChex server, and your account. Asked once, then remembered.")
                .font(.subheadline)
                .foregroundStyle(SoundChexTheme.ink500)
        }
        .padding(.top, 40)
        .padding(.bottom, 8)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String,
                       keyboard: UIKeyboardType, content: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(SoundChexTheme.ink300)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(SoundChexTheme.ink500))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .textContentType(content)
                .padding(12)
                .background(SoundChexTheme.base800, in: .rect(cornerRadius: 10))
                .foregroundStyle(SoundChexTheme.ink100)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(SoundChexTheme.ink300)
            SecureField("", text: text, prompt: Text("••••••••").foregroundStyle(SoundChexTheme.ink500))
                .textContentType(.password)
                .padding(12)
                .background(SoundChexTheme.base800, in: .rect(cornerRadius: 10))
                .foregroundStyle(SoundChexTheme.ink100)
        }
    }

    private var signInButton: some View {
        Button(action: submit) {
            HStack {
                if isWorking { ProgressView().tint(.white) }
                Text(isWorking ? "Signing in…" : "Sign in")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SoundChexTheme.accent, in: .rect(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .disabled(isWorking)
        .padding(.top, 4)
    }

    private func submit() {
        errorMessage = nil

        guard let url = normalizedServerURL(server) else {
            errorMessage = "That does not look like a valid address."
            return
        }
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password to sign in."
            return
        }

        isWorking = true

        Task {
            do {
                let found = try await session.fetchProfiles(server: url, email: email, password: password)

                // One profile with no PIN: skip the picker and sign straight in.
                if found.count == 1, !found[0].requiresPin {
                    await completeSignIn(profile: found[0], pin: nil)
                } else {
                    profiles = found
                }
            } catch {
                errorMessage = (error as? APIClient.APIError)?.errorDescription
                    ?? "Could not sign in."
            }
            isWorking = false
        }
    }

    /// Step two: mint the token for the chosen profile. Called from the picker.
    private func completeSignIn(profile: Profile, pin: String?) async {
        guard let url = normalizedServerURL(server) else { return }

        do {
            try await session.signIn(server: url, email: email, password: password,
                                     profile: profile, pin: pin)
            profiles = nil
        } catch {
            errorMessage = (error as? APIClient.APIError)?.errorDescription
                ?? "Could not sign in."
            profiles = nil
        }
    }

    /// Adds a scheme if the user typed a bare host, and drops any path — the same
    /// forgiving parse the web connect screen did.
    private func normalizedServerURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard let components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty else { return nil }

        var base = URLComponents()
        base.scheme = components.scheme
        base.host = host
        base.port = components.port
        return base.url
    }
}
