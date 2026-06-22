/// Reown (WalletConnect) project id — mobile only; inject at build/run time.
///
/// Copy [example.env] to `.env` (gitignored). Format: `KEY=value` per line —
/// no quotes, no spaces around `=`. Then run:
/// `flutter run --dart-define-from-file=.env`
const kReownProjectId = String.fromEnvironment('REOWN_PROJECT_ID');

/// True when [kReownProjectId] was passed via `--dart-define` / `.env`.
bool get hasReownProjectId => kReownProjectId.isNotEmpty;

/// Erebrus webapp origin for desktop browser sign-in.
/// Dev: https://dev.erebrus.io · Prod: https://erebrus.io
const kErebrusWebOrigin = String.fromEnvironment(
  'EREBRUS_WEB_ORIGIN',
  defaultValue: 'https://dev.erebrus.io',
);

/// Webapp route that performs wallet auth and redirects with a PASETO token.
const kErebrusDesktopAuthPath = '/auth';

/// Deep link the webapp redirects to after auth (`erebrusvpn://auth?token=…`).
const kErebrusAuthCallbackScheme = 'erebrusvpn';
const kErebrusAuthCallbackHost = 'auth';
const kErebrusAuthCallback = 'erebrusvpn://auth';

/// Gateway chain identifier for Solana wallet login.
const kSolanaChain = 'sol';

/// Public site + wallet redirect metadata (must match Reown Cloud allow-list).
const kErebrusSiteUrl = 'https://erebrus.io/';
const kErebrusSiteIcon = 'https://erebrus.io/favicon.ico';

/// Mobile Wallet Adapter requires the identity icon to be a **relative** path
/// (relative to the identity URI) — wallets reject an absolute icon URL and the
/// authorization fails. Reown/WalletConnect, by contrast, wants the absolute
/// [kErebrusSiteIcon]. Keep these separate.
const kErebrusMwaIconRelative = 'favicon.ico';

/// Native deep link — wallets return here after connect/sign (`erebrusvpn://…`).
const kErebrusNativeRedirect = 'erebrusvpn://';

/// Universal link placeholder for Reown metadata (host assetlinks when ready).
const kErebrusUniversalRedirect = 'https://erebrus.io/vpn';

/// Shown when Reown init runs without a project id in the build environment.
const kReownProjectIdMissingMessage =
    'REOWN_PROJECT_ID is not set. Copy example.env to .env, add your '
    'project id from cloud.reown.com, then run with '
    '--dart-define-from-file=.env';

/// macOS / iOS bundle id — sent to the webapp as `client_id`.
const kErebrusBundleId = 'com.erebrus.vpn';

/// Linux APPLICATION_ID.
const kErebrusLinuxApplicationId = 'com.erebrus.erebrus_vpn';

String reownOriginNotAllowedMessage(String relayOrigin) =>
    'Reown relay rejected this app (origin not allowed). In cloud.reown.com → '
    'your project → Allowlist, add: $relayOrigin and https://erebrus.io — then '
    'wait ~15 minutes and restart the app.';