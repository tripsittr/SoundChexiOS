import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The signed-in state: which server, and the token that proves who you are.
///
/// The server address and token are the only things that must survive a relaunch
/// — everything else (the library, downloads) is rebuilt from them. The address
/// is stored in UserDefaults (it is not a secret) and the token in the Keychain
/// (it is). Marked `@MainActor` because it drives the UI directly.
@MainActor
@Observable
final class Session {
    /// The base URL of the SoundChex server, e.g. https://el-laptop.tail7e590c.ts.net
    private(set) var serverURL: URL?

    /// The bearer token for the API, once signed in.
    private(set) var token: String?

    /// The API client, valid only while signed in.
    private(set) var api: APIClient?

    /// Bumped whenever the active identity changes (sign-in, profile switch), so
    /// views keyed on it rebuild and reload against the new token/profile.
    private(set) var identityGeneration = 0

    var isSignedIn: Bool { serverURL != nil && token != nil }

    private let defaults = UserDefaults.standard
    private let serverKey = "soundchex.serverURL"

    /// Rebuilds the session from stored credentials on launch.
    func restore() async {
        guard let stored = defaults.string(forKey: serverKey),
              let url = URL(string: stored) else { return }

        serverURL = url

        if let saved = Keychain.token(for: url) {
            token = saved
            api = APIClient(baseURL: url, token: saved)
        }
    }

    /// Step one: verify the credentials and list the account's profiles.
    ///
    /// A token is bound to one profile, so the user picks which before a token is
    /// minted. Throws (unauthorized, unreachable) so the sign-in screen can say
    /// why rather than staying on the form.
    func fetchProfiles(server: URL, email: String, password: String) async throws -> [Profile] {
        let client = APIClient(baseURL: server, token: nil)
        return try await client.profiles(email: email, password: password)
    }

    /// Step two: mint a token for the chosen profile and store the session.
    func signIn(server: URL, email: String, password: String,
                profile: Profile, pin: String?) async throws {
        let client = APIClient(baseURL: server, token: nil)
        let issued = try await client.login(
            email: email,
            password: password,
            profileID: profile.id,
            pin: pin,
            deviceName: Self.deviceName
        )

        serverURL = server
        token = issued
        api = APIClient(baseURL: server, token: issued)

        defaults.set(server.absoluteString, forKey: serverKey)
        Keychain.setToken(issued, for: server)
    }

    /// The profiles on this account, for the in-app switcher. No password: the
    /// token already proves the account.
    func myProfiles() async throws -> [Profile] {
        guard let api else { return [] }
        return try await api.myProfiles()
    }

    /// Switches to another profile on the same account — the person using the
    /// login changes, the login does not. Gets a fresh token and swaps it in
    /// without signing out.
    func switchProfile(to profile: Profile, pin: String?) async throws {
        guard let api, let serverURL else { return }

        let issued = try await api.switchProfile(
            profileID: profile.id, pin: pin, deviceName: Self.deviceName
        )

        token = issued
        self.api = APIClient(baseURL: serverURL, token: issued)
        Keychain.setToken(issued, for: serverURL)

        // The new profile has its own library/history; bump so the signed-in
        // views rebuild and reload against it.
        identityGeneration += 1
    }

    /// A human-readable name for this device, shown in the server's token list so
    /// a lost phone can be identified and revoked.
    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }

    /// Signs out: forgets the token and the API client. The server address is
    /// kept so the sign-in screen starts pre-filled.
    func signOut() async {
        if let api {
            try? await api.logout()
        }

        if let serverURL {
            Keychain.deleteToken(for: serverURL)
        }

        token = nil
        api = nil
    }
}
