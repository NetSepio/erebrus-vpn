# macOS code signing & Keychain (optional)

By default the app builds **unsigned** for local dev (`flutter run -d macos`). Session tokens use a **SharedPreferences fallback** when Keychain is unavailable.

To persist sign-in in **Keychain** (recommended for daily use), enable a personal **Apple Development** certificate.

## 1. Apple ID (free)

1. Open **Xcode** → **Settings** → **Accounts**
2. Click **+** → **Apple ID** → sign in with your personal Apple ID
3. Xcode creates a free **Apple Development** certificate automatically

## 2. Team ID

1. In **Accounts**, select your team
2. Copy the **Team ID** (10 characters, e.g. `AB12CD34EF`)

Or from Terminal:

```bash
security find-identity -p codesigning -v | head -5
```

## 3. Project signing config

```bash
cd /Users/User/Projects/NetSepio/erebrus-vpn
cp macos/Runner/Configs/Signing.xcconfig.example macos/Runner/Configs/Signing.xcconfig
```

Edit `macos/Runner/Configs/Signing.xcconfig`:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.Keychain.entitlements
```

`Signing.xcconfig` is gitignored (machine-local).

## 4. Run

```bash
flutter run -d macos
```

macOS may prompt to trust the new cert (**Keychain Access** or **System Settings → Privacy & Security**).

## Keychain password prompt (“login” / flutter_secure_storage)

There is **no separate Erebrus password**. macOS is asking to unlock the **login keychain** — normally the **same password you use to log into your Mac**.

If your Mac login password is **rejected**:

1. Your login keychain may be **out of sync** (common after a Mac password change).
2. Open **Keychain Access** → select **login** keychain (left sidebar).
3. If it shows locked: **Edit → Change Password for Keychain “login”** — set it to your **current** Mac login password.
4. Or delete stale items: search `erebrus` / `flutter_secure_storage` → delete those entries → sign in again in the app.

**Unsigned desktop builds** (`flutter run` without `Signing.xcconfig`) now **skip Keychain entirely** and store the session in local prefs — you should not see this prompt after a hot restart. Keychain is only used when you enable Development signing (section 3 above).

## 5. Verify Keychain

After sign-in, logs should **not** show:

- `secure storage write failed: -34018`
- `session saved via desktop fallback`

## Unsigned mode (default)

If `Signing.xcconfig` is missing:

- Build works without a Development certificate
- `DebugProfile.entitlements` has no Keychain groups
- Auth session uses the desktop fallback in `lib/auth/auth_session_store.dart`
- Gateway subscription is still tied to your **wallet on the server** — only local token storage differs

## VPN on macOS

macOS uses a signed, sandboxed `ErebrusTunnel` Network Extension and the
universal `Libbox.xcframework`. It no longer launches a CLI, requests
administrator elevation, or changes system proxy settings. Build the framework
and configure the target before running:

```bash
./scripts/build-libbox-macos.sh
ruby ./scripts/setup-macos-tunnel.rb
flutter run -d macos
```

The first connection asks for normal macOS VPN configuration approval. App
Store and development provisioning must include Packet Tunnel Provider and the
shared App Group on both bundle identifiers.

Check **Egress IP** on the server card after connect.

## Xcode UI alternative

Instead of `Signing.xcconfig`:

1. Open `macos/Runner.xcworkspace`
2. Select **Runner** → **Signing & Capabilities**
3. Enable **Automatically manage signing**, choose your **Team**
4. Add **Keychain Sharing** capability (empty group is fine for debug)

## Production / Release

`Release.entitlements` already includes Keychain access groups. For public
distribution outside the Mac App Store, install a **Developer ID Application**
certificate, sign with Hardened Runtime-compatible entitlements, and submit the
archive to Apple's notarization service. An **Apple Distribution** certificate
is for App Store workflows; it does not replace Developer ID signing for a ZIP
downloaded from the web.
