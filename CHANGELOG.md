# Changelog

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
