# Getting a build onto TestFlight

Everything in the repo is ready. What remains is account setup on Apple's side,
which cannot be done from here.

## Once, before the first upload

1. **Apple Developer Program** — $99/year, and the account must be *active*.
   A free account cannot use TestFlight at all. Team `7GSWB72PH6` is already
   in `project.yml`.

2. **Register the bundle id.** developer.apple.com → Certificates, Identifiers
   & Profiles → Identifiers → `+`. Use **`app.soundchex.ios`**, exactly — it
   must match `PRODUCT_BUNDLE_IDENTIFIER`. Enable no capabilities beyond the
   defaults; the app needs none (background audio is an Info.plist mode, not
   an entitlement).

3. **Create the app record.** appstoreconnect.apple.com → Apps → `+` → New App.
   - Platform: iOS
   - Name: SoundChex (must be unique across the whole App Store — if it is
     taken, the *listing* name can differ from the app's display name)
   - Primary language, and the bundle id from step 2
   - SKU: anything private, e.g. `soundchex-ios`

## Each upload

1. `xcodegen generate`
2. Xcode → the scheme's destination must be **Any iOS Device (arm64)**, not a
   simulator. Archive is greyed out for a simulator destination, which is the
   usual first confusion.
3. **Product → Archive**
4. Organizer opens → **Distribute App** → **TestFlight & App Store** → Upload
5. Let Xcode manage signing. It creates the distribution certificate and
   profile the first time.

Processing takes 5–30 minutes. The build appears in App Store Connect →
TestFlight.

## Testers

- **Internal** (up to 100, must be on your team): no App Review. The build is
  installable as soon as it finishes processing. This is the fast path.
- **External** (up to 10,000): needs a review pass on the *first* build of each
  version. Usually a day or two. Later builds of the same version go straight
  through.

## Bumping the version

`CURRENT_PROJECT_VERSION` must increase for **every** upload — App Store
Connect refuses a build number it has seen before for that version, and the
error arrives after the upload, not before.

`MARKETING_VERSION` follows `Plans/Versioning.md`: a name per minor, and the
name must be in `AppRelease.swift` or it does not ship.

## App Review notes

Paste this into App Store Connect → the build → **Notes for Review**. It
pre-empts the two questions this app reliably attracts.

> SoundChex is a client for a media server the user runs themselves. There is
> no SoundChex-operated backend: the app connects only to a server address the
> user enters, on hardware they own.
>
> **Signing in to test.** The app needs a server to be useful. A test server
> and credentials are in the demo account fields above. [FILL THIS IN — a
> reviewer who cannot sign in will reject the build.]
>
> **Why NSAllowsArbitraryLoads is set.** Users connect to their own servers,
> which are usually on private addresses (a home LAN, or a Tailscale tailnet).
> Those addresses cannot be issued public TLS certificates, so requiring HTTPS
> would make the app unable to reach the very servers it exists to serve. No
> traffic goes to any server the user has not explicitly entered.
>
> **Media.** The app plays the user's own files from their own server. It does
> not acquire, index or link to any content, and ships with none.

## What is already done in the repo

- `ITSAppUsesNonExemptEncryption: false` — without it, every upload stops with
  a "Missing Compliance" prompt before testers can install.
- `Resources/PrivacyInfo.xcprivacy` — required since May 2024; an upload
  without one is rejected. Declares no data collection, and the two
  required-reason APIs actually used (UserDefaults CA92.1, disk space E174.1).
- App icon: 1024×1024, no alpha channel. Apple rejects icons with transparency.
- Version and build resolve from the build settings, so Settings shows the
  real release.

## Known gaps to expect

- **No demo account exists yet.** Fill in the review notes above before
  requesting external testing, or the first review will fail on "we could not
  sign in".
- The export-compliance answer assumes only standard HTTPS. That is true
  today; revisit if custom crypto is ever added.
