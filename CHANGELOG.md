# Changelog

## Unreleased — app disguise and leak lockdown

### TL;DR

- The app can wear another name and icon in the launcher: Notes, Calculator or
  Weather. The VPN notification follows the disguise, so a "Notes" icon is not
  given away by a notification that says Erebrus.
- Screenshots, screen recording and the recents thumbnail are blocked on
  Android; on iOS and macOS the UI is covered whenever the app is not frontmost.
- Backups can no longer lift the app's stored keys off a device, and cleartext
  networking is narrowed from "anything" to the engine's own loopback ports.
- The app no longer offers to verify a gating NFT; the gateway stopped granting
  that entitlement and now answers 410.

### Added

- **Launcher disguise.** The `MAIN`/`LAUNCHER` filter moves off `MainActivity`
  onto four `<activity-alias>` entries, exactly one enabled at a time, so the
  launcher's name and icon change without a reinstall. Settings → App disguise
  picks one. The incoming alias is enabled *before* the outgoing one is
  disabled: several OEM launchers drop an app that passes through a moment with
  no enabled launcher component, and the only way back is to reinstall. The
  `erebrusvpn://` deep link stays on `MainActivity`, so sign-in survives every
  switch.
  - The copy lives in `lib/settings/disguise_profile.dart` and the aliases in
    the manifest; `test/disguise_profile_test.dart` fails if they drift apart,
    including the launcher labels and the icon resources, because nothing at
    runtime notices — the icon simply fails to change.
  - A disguise hides that Erebrus is *installed*. It does not protect what is
    stored: an unlocked device still hands everything over. The picker says so,
    and so should the marketing copy — "discreet", never "seizure-proof".

### Changed

- `FLAG_SECURE` on Android blanks the recents thumbnail and refuses screenshots
  and screen recording. This matters more with a disguise, not less: a
  calculator icon whose recents preview shows a node list defeats itself.
- iOS and macOS have no equivalent flag, so `PrivacyCover` in
  `lib/view/root_view.dart` covers the UI on `inactive` — the state the OS
  snapshot is taken in — and uncovers on `resumed`.
- `android:allowBackup="false"`, an empty `data_extraction_rules.xml` and
  `fullBackupContent="false"`: `adb backup` and cloud or device-to-device
  transfer can no longer carry off `EncryptedSharedPreferences`, which holds the
  session token, the WireGuard private keys and the stealth credentials.
- `android:usesCleartextTraffic="true"` is replaced by a network security config
  that permits cleartext to `127.0.0.1` and `localhost` only — the Clash API on
  :9090 and the mixed inbound on :10808. Everything that leaves the device is
  HTTPS, so the blanket flag was permitting far more than the app has ever used.

### Removed

- NFT gating. The gateway stopped granting a personal NFT entitlement and
  returns 410 on `POST /api/v2/subscriptions/nft/refresh`, so this removes an
  offer the app could not honour: `refreshNftEntitlement` on the auth client and
  the controller, `nftGatingEnabled` on `EntitlementState`, `kNftEntitlementDays`
  and the NFT badge in settings. The entitlement `source` doc now lists
  `onchain`, which is what prepaid USDC terms arrive as.

## 1.0.10+11 — 2026-11-17

### TL;DR (store release notes)

- Coming back to the app no longer flashes "Tunnel stalled" while the
  connection is checked.
- The private browser shows web pages in dark mode, with a setting to turn it
  off.
- A cleaner, more consistent browser: one toolbar on desktop, a stop button
  while pages load, and full tab titles.

### Fixed

- When the app was restored or brought to the foreground, the connect screen
  showed "Tunnel stalled" for a moment before the health check ran. A tunnel
  adopted from the system now reads "Verifying tunnel" until its first egress
  probe answers, and a tunnel that was already verified stays "Protected".
- On phones, the browser menu, tab switcher and link menu open over the
  dimmed page instead of a blank area.
- Tapping the address bar selects the whole address, so typing replaces it
  instead of being appended to the current URL. After editing, the address
  scrolls back to its start.
- Browser toasts sit above the bottom bar instead of covering it.
- Tab titles are no longer cut to 24 characters; each view shortens them only
  when it runs out of room.

### Changed

- The app uses a dark appearance on every platform, so sites with their own
  dark theme use it in the browser. Light-only pages are darkened
  automatically, with photos and video kept in their real colours. "Dark web
  pages" in the browser menu turns this off.
- Browser menus, the tab switcher, the link menu and the loading, error and
  "Connect to browse" screens share the app's sheet and panel styling, and
  every browser row uses the same side margin.
- While a page loads, the reload button becomes a stop button and a progress
  bar shows under the address bar.
- On desktop, back, forward, home, the tab count and the menu are in one
  toolbar; back and forward are greyed out when there is nowhere to go, and
  the bottom bar is gone. "Connect to browse" has an "Open VPN" button.

### Build

- CI and release builds are pinned to Flutter 3.47.7, the version this release
  was tested on. Flutter 3.50 deprecates `package:flutter/material.dart`,
  which failed `flutter analyze` when CI followed the latest stable.
- The Linux release builds on Ubuntu 24.04, so the bundle runs on the same
  distributions as before. Deprecation warnings from system libraries no
  longer stop the Linux build.

## 1.0.9+10 — 2026-11-01

### TL;DR (store release notes)

- Full servers are marked in the server list, and picking one no longer
  disconnects you.
- Server ping is accurate while you are connected.
- A server that connects but passes no traffic is reported after one attempt,
  and the app reconnects you to your previous server.

### Fixed

- Nodes that report `accepting_clients: false` are marked **Full** in the
  picker and can't be picked. Picking a full node no longer disconnects a
  working tunnel.
- Ping is no longer measured through the VPN. Probes through the tunnel
  answered locally and showed 5–16 ms for every node. While connected, the
  picker shows the pings measured before connecting, or none if none exist.
- The node picker opens on the tab that holds the current node. Before, a
  public node run by an organization opened an empty Private tab.
- A server whose tunnel comes up but forwards no traffic now gets one pass
  over its transports, not two. The app then shows "<node> is not passing
  traffic — pick another node". When the user was switching away from a
  working node, the app reconnects to that node, with the kill switch
  blocking traffic in between.

### Build

- CI builds the macOS and iOS apps (unsigned) on every pull request and push
  to `main`, with sing-box libbox cached between runs. Build failures are
  repeated as workflow annotations, so they can be read without signing in.

## 1.0.8+9 — 2026-11-01

### TL;DR (store release notes)

- Fixes a crash on Android when connecting to a VPN server.
- Connects to servers that assign both an IPv4 and an IPv6 address.
- Fixes the app freezing on the splash screen after returning from a wallet
  app such as Jupiter.

### Fixed

- Android 1.0.7 crashed on connect: its sing-box core was built with Go 1.27,
  which leaves an http2 symbol that sing-box v1.11.15 links to unresolved, so
  the library failed to load. Release builds use Go 1.26 again, and the libbox
  build now fails if any Go symbol is left unresolved.
- WireGuard connections failed when a node assigned a dual-stack address list
  (for example `100.64.0.8/32, fd00:64:64::8/128`); each address is now passed
  to sing-box as its own prefix, on every platform.
- The app no longer freezes on the splash screen when Android restarts it
  without ending the process (for example after returning from a wallet such
  as Jupiter on the Seeker).
- iOS archives build with Xcode 27, which rejected an unused CloudKit check in
  the scene delegate.

## 1.0.7+8 — 2026-10-29

### TL;DR (store release notes)

- Stay signed in: your login now renews automatically in the background, so
  you are no longer signed out every day. Open the app at least once every 30
  days to keep your session.
- Safer VPN protection: the app no longer reports you as protected before the
  tunnel is verified, and the kill switch no longer locks your connection when
  the very first connect fails.
- Private browsing through the VPN on Windows and Linux desktops.
- A redesigned account details screen with a clearer account-deletion flow.
- Clearer messages when you reach your plan's device limit or a device is
  paused.

### Added

- Persistent sign-in with rotating refresh tokens on Android, iOS, macOS,
  Windows, and Linux. Access tokens renew shortly before they expire and once
  more after an `ACCESS_TOKEN_EXPIRED` rejection; the 30-day refresh window
  slides forward with each renewal. Existing logins are upgraded in place, so
  updating does not require signing in again.
- Credentials are stored as one item in the platform's secure storage, and
  renewals are serialized across isolates, so
  concurrent requests never spend the same single-use refresh token twice.
- Proxy-routed in-app browsing on Windows and Linux desktops.

### Improved

- Account details and account deletion in Settings have been redesigned.
- Device-limit, paused-device, and billing errors are shown in plain words; the
  remaining retired free-trial text has been removed.
- Wallet and Google sign-in failures show readable error messages.
- Google sign-in on Android is shown only on builds whose signing key is
  registered with Google, and never on the Solana dApp Store build.

### Fixed

- The VPN no longer claims protection before the tunnel is verified, and the
  kill switch is enforced while connected.
- A failed first connection no longer engages the kill switch; an unverified
  blocking tunnel is torn down, and connect errors are logged.
- Sign-in callbacks (deep links) are delivered reliably on every platform,
  including when the app is launched by the callback.
- Platform-specific calls are guarded on platforms that do not support them.
- The in-app browser validates URLs before opening them in a new tab.
- Linux packages install the bundled sing-box runtime and desktop entry in the
  correct locations.

## 1.0.6+7 — 2026-08-21

### TL;DR (store release notes)

- Invite friends and earn XP — your referral card, invite code, redeem option,
  and lifetime XP now appear as soon as you sign in.
- Pending organization invites show up right on the Settings screen, so you
  never miss a workspace invitation.
- The connection timer now shows your true session length, even after
  reopening the app or switching tabs mid-session.
- Cleaner in-app browser: the new-tab address bar is empty and ready to type.
- Polished sign-in screen and more accurate referral wording.

### Improved

- The referrals card (invite code, invited/qualified counts, and the redeem-a-
  code field) now loads on sign-in and on session restore instead of staying
  hidden until a code was already redeemed, making the invite/XP flow reachable.
- Lifetime XP is now shown on the referrals card, sourced from the rank endpoint
  (the authoritative XP source) rather than assumed to arrive with the referral
  or profile responses; the "already applied" state is read from the gateway's
  authoritative binding flag.
- Pending organization invites are fetched on login/restore, so the Settings
  "Pending invites" badge and row appear without first opening the
  Organizations sheet.
- The VPN connection timer is anchored to the tunnel's real connect time,
  persisted across app restarts, so elapsed duration stays accurate through view
  rebuilds, tab switches, and cold starts.
- Login screen now reads "Welcome to Erebrus VPN", and the referrals copy
  reflects how XP is actually earned (no more unbacked "claim XP" wording).
- On macOS, closing or minimizing the window now hides Erebrus to the menu bar
  and removes its Dock icon; opening it from the tray restores the window.

### Fixed

- Signing out now clears pending organization invites and account-deletion
  request state, preventing one account's data from lingering when another
  account signs in during the same session.
- The in-app browser address bar no longer surfaces the internal
  `erebrus://home` scheme on the private start page — it stays empty so the
  "Search or enter address" hint is shown.

## 1.0.5+6 — 2026-08-18

### Improved

- Expired gateway sessions now automatically sign out instead of leaving the
  account and subscription UI in a stale authenticated state.
- Stored sessions are revalidated when the app starts and resumes, with a clear
  prompt to sign in again when authentication has expired.
- Settings now reflects organization-derived plans and no longer advertises the
  retired personal free-trial flow.

### Fixed

- Gateway HTTP errors retain their status and machine-readable code so expired
  sessions can be distinguished from permission and network failures.
- Private cached VPN credentials are not reused after a session-expiry response.

## 1.0.4+5 — 2026-08-07

### Added

- Human-readable personal and business plan labels across subscriptions and
  organization membership details.
- Connection-aware macOS menu-bar icon states: adaptive black/white while the
  VPN is live and a subdued icon while disconnected or transitioning.

### Improved

- Desktop navigation now uses a persistent branded sidebar with live VPN
  status, a wider default window, and a full-width private-browser workspace.
- Onboarding and sign-in layouts stay centered at a readable width in desktop
  windows while retaining their existing mobile behavior.
- Desktop navigation labels now use the same casing as mobile navigation.
- Organization role and plan metadata handles missing legacy plan values and
  long labels without misleading text or overflow.

### Fixed

- Live gateway coverage no longer assumes an obsolete node region while still
  validating production node display data.

## 1.0.3+4 — 2026-07-25

### Added

- Sign in with Apple on iOS and macOS, alongside the existing platform login
  choices. macOS also retains browser and token-based sign-in.
- Guest access from the login screen, with back navigation across supported
  form factors.
- Organization switching and organization-scoped VPN nodes. The server picker
  separates public nodes from private organization nodes and lets members
  change the active organization before connecting.
- Active transport reporting in connection diagnostics, the connect screen,
  desktop tray, and browser session status.
- Brave Search in the private browser and working network-tool shortcuts for
  FAST.com, public IP, DNS leak, WebRTC leak, IPv6, and Cloudflare connection
  diagnostics.
- VPN On Demand support for the iOS system tunnel profile.
- A sandboxed macOS Packet Tunnel Provider with native WireGuard,
  VLESS/REALITY, and Hysteria2 support for Mac App Store distribution.

### Improved

- Mobile guest and configuration-import layouts scale across compact screens
  without clipped controls or unnecessary scrolling.
- WireGuard/stealth controls now reflect whether a usable configuration exists
  and clearly show the transport selected by Auto mode.
- iOS tunnel status delivery is marshalled onto Flutter's platform thread.
- VPN health checks, gateway refreshes, and browser proxy synchronization avoid
  overlapping work that previously caused slowdowns and excessive memory use.
- Android release packaging is explicitly ARM64-only so every supported variant
  includes the native sing-box VPN core.
- Apple app and packet-tunnel targets now inherit the canonical Flutter version.
- Desktop config import is file-only and no longer links or requests camera
  access; Android and iOS retain QR-camera import.

### Fixed

- Missing iOS photo-library purpose metadata required by App Store validation.
- Missing iOS packet-tunnel bundle version during device installation.
- Apple authorization-code forwarding during native Sign in with Apple.
- macOS secure-storage failures now fall back safely when Keychain access is
  unavailable under the current signing identity.
- Android 7 notification and network-callback compatibility.
- Android WebView proxy capability checks and platform-specific plugin calls.
- Browser single-word searches incorrectly being treated as hostnames.
- Several iOS connection hangs, native callback threading issues, and tunnel
  health/probe performance problems.
- Missing macOS Utilities category metadata required for Mac App Store archive
  validation.
