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

## VPN on macOS (unsigned)

1. Install the CLI: `./scripts/setup-macos-dev.sh`
2. Tap **Connect** — sing-box starts as a normal process with a local mixed proxy on `127.0.0.1:10808`
3. The app sets **system HTTP/HTTPS/SOCKS proxy** on your active network services so **Safari and Chrome** use the same path as the in-app egress check

Unsigned desktop builds use **proxy mode** (not TUN). That avoids the administrator password prompt and fixes the case where the in-app browser shows the correct egress IP but system browsers have no internet (TUN DNS is unreliable without a signed Network Extension).

Non-browser apps may not use the VPN until you ship a signed Network Extension build.

**Disconnect** in the app before quitting — proxy settings are restored on disconnect. If the Mac has no internet after a crash:

```bash
networksetup -setwebproxystate Wi-Fi off
networksetup -setsecurewebproxystate Wi-Fi off
networksetup -setsocksfirewallproxystate Wi-Fi off
```

(Replace `Wi-Fi` with your service from `networksetup -listallnetworkservices`.)

For production-quality VPN without a password prompt each session, use a **signed Network Extension** + `Libbox.xcframework` (see `docs/BUILD.md`).

Check **Egress IP** on the server card after connect.

## Xcode UI alternative

Instead of `Signing.xcconfig`:

1. Open `macos/Runner.xcworkspace`
2. Select **Runner** → **Signing & Capabilities**
3. Enable **Automatically manage signing**, choose your **Team**
4. Add **Keychain Sharing** capability (empty group is fine for debug)

## Production / Release

`Release.entitlements` already includes Keychain access groups. Use a Distribution certificate and notarization for shipping outside the Mac App Store.