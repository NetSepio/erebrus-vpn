/// Reown (WalletConnect) project id — Solana-only wallet auth.
const kReownProjectId = String.fromEnvironment('REOWN_PROJECT_ID');

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