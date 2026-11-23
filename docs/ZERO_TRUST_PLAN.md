# Zero-Trust Environment — implementation plan

Seven tracks, mapped to concrete changes in `erebrus-vpn` (app), `erebrus`
(node), `erebrus-gateway` (control plane), with one track landing in
`erebrus-mcp`. Written against the code as of `erebrus-vpn@fb31c1d`,
`erebrus@994de49`, `erebrus-gateway@6a8358e`, `erebrus-mcp@b9cf782`.

This is the rationale document. The per-repo work orders, all on branch
`feat/zta-plan`, are `docs/ZTA_HANDOVER.md` (this repo),
`erebrus/docs/ZTA_PLAN.md`, `erebrus-gateway/docs/ZTA_PLAN.md` and
`erebrus-mcp/docs/ZTA_PLAN.md`.

**Env-var budget: zero new env vars.** Every track below reuses existing config
(`GATEWAY_URL`, `SHIELD_ADMIN_URL`, `FIREWALL_DNS_ADDR`, `WG_DNS`,
`CHAIN_REGISTRATION`, `SOLANA_RPC_URL`, `EVM_RPC_URL`) or moves the knob into
`platform_settings` and config tables in the DB, where operators already manage
node state and where it can be changed without a deploy. Items where an env var
would have been the lazy answer are called out as they come up. The branch is
net **negative** three: retiring NFT gating deletes `NFT_GATE_CHAIN`,
`NFT_GATE_CONTRACT` and `NFT_GATE_RPC_URL`.

One carve-out: `erebrus-mcp` is a CLI tool an agent spawns, not a deployed
service, and it is already configured entirely by env. It adds two
(`EREBRUS_SINGBOX_PATH`, `EREBRUS_EGRESS_MAX_SESSIONS`); everything else there is
a tool argument, decided per call by the agent.

## What each track buys in the positioning

| Adversary | Today | After |
| --- | --- | --- |
| Someone glancing at the phone | app sits in the launcher under its own name | disguised icon + name (T1) |
| Network DPI / ISP | stealth carriers already defeat it | unchanged (already strong) |
| A single node operator | sees your IP **and** your destinations | two-hop splits them across operators (T2) |
| National-scale blocking | data plane survives, control plane dies | bootstrap carrier reaches the gateway (T3) |
| The resolver itself | plaintext :53 inside the tunnel, org policy unenforced | DoH/ODoH + live org policy (T4) |
| The gateway itself (down, seized, or censored) | no service: no plan check, no node list | on-chain node + subscription registry (T5) |
| An AI agent with no privacy of its own | agent dials from its own IP, geofenced out | MCP egress through Erebrus (T6) |
| A user or agent with no card | fiat only | USDC subscriptions on Ethereum and Solana (T7) |

Claim precisely: *no single party holds both identity and destination*. That is
what T2 + T4 make true, and it is the only honest "zero trust" sentence here.

On the device row, be equally precise: a disguise hides that Erebrus is
*installed*. It does not protect what is stored. Secrets at rest keep today's
posture (Keystore/Keychain via `ErebrusSecureStorage`), which an unlocked device
hands over. PIN-wrapped keys and a duress wipe are deferred — see the note under
Track 1 — so marketing copy for T1 should say "discreet", never "seizure-proof".

---

## Track 1 — App disguise and leak lockdown (app repo only)

### 1a. Free wins first (do these in the same PR, they are one-liners)

- `android/app/src/main/AndroidManifest.xml` — `android:allowBackup` is **not
  set**, so it defaults to `true`: `adb backup` and cloud backup can lift
  `EncryptedSharedPreferences` off a seized device. Add
  `android:allowBackup="false"`, `android:dataExtractionRules="@xml/data_extraction_rules"`
  (empty ruleset) and `android:fullBackupContent="false"`.
- Same file: `android:usesCleartextTraffic="true"` is broader than it needs to be.
  Replace with a network-security-config that permits cleartext only for
  `127.0.0.1` (the Clash API on :9090 and the mixed inbound on :10808).
- `MainActivity.kt` — add `FLAG_SECURE` so the recents thumbnail and screenshots
  of the app are blank. This matters more with a disguise, not less: a calculator
  icon whose recents preview shows a node list defeats itself. iOS equivalent is
  an opaque overlay on `AppLifecycleState.inactive`, driven from a small
  `AppLifecycleListener` in `lib/view/root_view.dart`.

### 1b. App disguise (Android activity-alias)

- `android/app/src/main/AndroidManifest.xml`: move the `MAIN`/`LAUNCHER`
  intent-filter **off** `.MainActivity` onto `<activity-alias>` entries, one per
  disguise (`.LauncherDefault` enabled, `.LauncherNotes`, `.LauncherCalc`,
  `.LauncherWeather` disabled). Keep the `erebrusvpn://` `VIEW` filter on
  `.MainActivity` so deep links survive alias switching.
- New `android/app/src/main/kotlin/com/erebrus/vpn/AppDisguise.kt`:
  `setComponentEnabledSetting` with `DONT_KILL_APP`. **Order matters** — enable
  the new alias *before* disabling the old one, or the icon disappears from the
  launcher on several OEM skins. Expose `disguise.list` / `disguise.current` /
  `disguise.set` on the **existing** `com.erebrus.vpn/methods` channel
  (`lib/platform/app_channels.dart`) — no new channel.
- `ErebrusVpnService.kt`: the foreground notification is the real tell. Take
  title/text/small-icon from the active disguise profile. The system VPN key
  glyph cannot be suppressed — say so in the UI copy rather than implying it can.
- iOS has no activity-alias. Closest is `UIApplication.setAlternateIconName`:
  alternate icons in `ios/Runner/Info.plist` (`CFBundleAlternateIcons`), icon
  only — the display name stays. Ship 2–3 icons and label the setting
  "Alternate icon" on iOS, "Disguise" on Android.
- Desktop: profile drives `window_manager` title + tray tooltip in
  `lib/platform/desktop_shell.dart`.
- Dart: `lib/settings/disguise_profile.dart` (id, label, icon asset, notification
  copy, per-platform support), persisted at `settings.disguise_profile` by
  `AppSettingsController`; UI in `lib/view/settings/privacy_view.dart`.
- Tests: `test/disguise_profile_test.dart` — every profile declares an alias name
  that exists in the manifest, and the Android alias set in the manifest matches
  the Dart profile list exactly. That pairing is the thing that silently rots
  when someone adds a profile without the alias (symptom: app vanishes from the
  launcher), so make it a test rather than a review habit.

What the disguise covers, and what it does not — put this in the setting's help
text so nobody over-trusts it:

- **Covered**: the launcher icon and the launcher label, the foreground-service
  notification, and (desktop) the window title and tray tooltip.
- **Not covered**: Settings → Apps and Settings → VPN still list the real app
  name and package `com.erebrus.vpn`; the system VPN key glyph in the status bar
  stays; Play Store "my apps" shows the real listing; `pm list packages` and any
  MDM inventory see through it immediately.
- **Operational caveats**: a pinned home-screen shortcut to the old alias breaks
  on switch, and some launchers cache the icon for a few seconds, so the UI
  should say "may take a moment to update" rather than appear broken. Alias
  enable/disable state survives app updates; a reinstall resets to the default
  alias. Flutter itself is unaffected — the aliases all target `.MainActivity`
  and the engine never knows which one launched it.

### Deferred: PIN + duress PIN

Cut from this scope. What that leaves on the table, so the decision is
reversible later: the session token, the WireGuard private key and the cached
credential bundles stay readable to anyone with the device unlocked, because
`ErebrusSecureStorage` is unlocked whenever the OS user is. A PIN is only worth
building if it wraps an actual vault key over those writes — a lock screen on
its own is theatre, which is part of why deferring it is the right call rather
than shipping a weak version.

The two one-liners in 1a are independent of this and still worth taking: they
close off `adb backup` and the recents thumbnail, which no PIN would have
covered anyway.

**No new env vars. No gateway or node change.**

---

## Track 2 — Two-hop VPN

### The key finding: this is almost entirely client-side

The node already does `FORWARD` + `MASQUERADE` for the whole client subnet
(`erebrus/internal/netcidr/cidr.go:129-131`), so an entry node already forwards
UDP to a second node's `:51820`. **No node change. No gateway change.**

### `erebrus-vpn`

- `lib/vpn/vpn_models.dart` — add `SingboxConfigBuilder.buildTwoHop({entryBundle,
  exitBundle, entryTransport, entryPrivateKey, exitPrivateKey, …})` producing two
  `endpoints`: `wg-entry` (peer = entry node, `detour` = carrier tag when the
  entry hop is stealth) and `wg-exit` (peer = exit node, `detour: 'wg-entry'`),
  with `route.final = 'wg-exit'`. Details that will bite:
  - The direct bypass rule from `_localRouteRules(wgServerHost:)` must apply to
    the **entry** host only. Bypassing the exit host sends hop 2 around hop 1 and
    silently degrades to single-hop — assert this in a test.
  - MTU ladder: entry 1280, exit 1200 (entry − 80). The current builder hardcodes
    1280 in `_buildDirectWireGuard`; parameterise it.
  - Pre-resolve both peers via `resolveDialHosts` and pass the exit peer as an IP
    literal; a hostname there would need DNS before hop 2 exists.
  - `_dnsConfig`: `dns-remote` detours `wg-exit`; `dns-direct` bootstraps the
    entry carrier host only.
- `lib/vpn/vpn_controller.dart` — do **not** add a fourth `ConnectMode`; that
  multiplies the transport matrix. Add `twoHop` (bool) + `entryNode` to the
  controller, and pick transports per hop: stealth on hop 1 (that is what beats
  DPI), plain WireGuard on hop 2 (keeps the overhead sane). Provision two bundles
  with the existing `provisionClient` — gateway rows are keyed by
  (user, node, wg_public_key), so two nodes give two rows with no gateway work.
- Generate a **separate exit keypair** (`erebrus_wg_private_hop2`) rather than
  reusing the single stored key. Cheap, and it keeps the two hops from sharing an
  identifier in the gateway's client table.
- `lib/vpn/vpn_session_store.dart` — persist `entry_node_id` / `exit_node_id` so
  a process restart rebuilds the right UI.
- Node selection: enforce `entry.org.slug != exit.org.slug` in the picker
  (`lib/view/home/server_sheet.dart`). Different operators per hop is the whole
  point; same-operator two-hop is just latency. `VpnNodeOrg` is already on every
  node from discovery, so this is free.
- Tests: `test/vpn_two_hop_config_test.dart` — endpoint graph, detour chain,
  exactly one direct bypass, MTU ladder; plus a case in
  `test/singbox_runtime_integration_test.dart` so the bundled `sing-box check`
  validates it. (That suite skips on macOS — simulate Linux before tagging.)

**No new env vars.**

---

## Track 3 — Gateway reachability under blocking

The hard one. `gateway.erebrus.io` (`lib/vpn/gateway_config.dart:9`) is the single
control-plane dependency; the DoH fallback in `gateway_http.dart` handles DNS
poisoning but nothing about IP or SNI blocking.

### First, tell the two failures apart

`GatewayHttp.isTransientNetworkError` lumps them together. Add classification:
DNS failure (handled by DoH today) vs. **reachability** failure — TLS reset after
ClientHello, or connect timeout to an address that resolved fine. Only the second
should escalate to a bootstrap carrier. Put this in `lib/vpn/gateway_errors.dart`
next to the existing envelope parsing.

### `erebrus` (node) — a destination-restricted bootstrap user

`internal/stealth/stealth.go` pins every carrier connection to
`127.0.0.1:<wg-port>` via a `RouteOptionsActionOptions` override. That pin is
load-bearing (it stops the node being an open proxy) and must stay. Add one
narrow exception:

- A second VLESS user (`"bootstrap"`, its own UUID from
  `internal/stealth/secrets.go`) on the existing inbound.
- A route rule **before** the override: match `AuthUser: ["bootstrap"]` +
  `domain: <host of cfg.GatewayURL>` + `port: 443` → `direct`. Everything else
  from that user still hits the override, so the worst a leaked bootstrap
  credential buys is a proxy to the gateway's own API.
- `GATEWAY_URL` already exists on the node (`internal/config/config.go:131`), so
  **no new env var**. Every node can run this unconditionally; which nodes are
  *published* as bootstrap is a gateway decision (below), not node config.
- Hysteria2 is **left out of v1**: VLESS/REALITY on tcp/443 is the carrier that
  survives the most aggressive filtering, and one hole in the carrier pin is
  easier to reason about than two.

### `erebrus-gateway` — publish and rotate the descriptors

- `GET /api/v2/bootstrap` (public, rate-limited via the existing
  `s.rateLimit(...)` pattern in `internal/api/server.go`): a small signed list of
  bootstrap descriptors (host, port, REALITY pbk/sid, bootstrap UUID), signed by
  the gateway key so a stale app can still verify a rotation.
- Bootstrap eligibility as a column on the node row + an admin endpoint — not a
  node env var. The gateway already stores node endpoints; this keeps rotation
  central and lets you pull a burned node in seconds.
- `internal/nodehub/messages.go` — the gateway **re-marshals its own typed
  `Capabilities` struct** (`internal/nodehub/hub.go:224`), so unknown capability
  fields a node sends are dropped. Any new flag needs ~3 lines here plus
  `docs/ws-protocol.md` (FROZEN v2.0 — edit the doc first, then both repos; the
  node mirrors it in `internal/gatewayclient/messages.go`).

### `erebrus-vpn` — the escalation ladder

- `lib/vpn/bootstrap_config.dart` — compile-time default descriptors (code, not
  env) + a cache in secure storage, refreshed from `GET /api/v2/bootstrap`
  whenever the gateway *is* reachable. Out-of-band path for free: accept a
  signed `erebrusvpn://bootstrap?…` blob through the existing deep-link handler
  and QR scanner (`lib/view/guest/guest_scan_view.dart`,
  `lib/guest/guest_config_store.dart`). That is the distribution channel that
  actually survives a shutdown — a screenshot in a group chat.
- `lib/vpn/bootstrap_tunnel.dart` — on **desktop**, run the engine proxy-only
  (`useSystemTunnel: false` already yields the `mixed-in` inbound on
  127.0.0.1:10808) and point the gateway client at it with
  `HttpClient.findProxy`. Note the warning already in `gateway_http.dart:20`:
  use `findProxy`, never `connectionFactory` — the latter breaks SNI.
  On **mobile**, `ErebrusVpnService` always establishes a TUN, so the honest v1
  is a short-lived real tunnel to the bootstrap node (reuse `_connectTo` with a
  synthetic bundle), used for sign-in/discovery, then reconnect to the chosen
  node. Cost: one visible connect/disconnect cycle. Benefit: no new native code.
  A no-TUN libbox path in `SingboxBridge.kt` is the follow-up, not the blocker.
- Trigger: after N consecutive *reachability* failures, or immediately when the
  user taps "Can't sign in?" — make it manual-first, because an automatic
  fallback that misfires is a support nightmare.

---

## Track 4 — Shield as DoH/ODoH + org policy (node-side, no app update)

### The gap worth fixing first: org policy is silently dropped

`erebrus/internal/firewall/client.go:108` — `syncShield` ignores the
`SyncPayload` entirely and only calls `/control/cache_clear`. Gateway-managed
firewall rules (`erebrus-gateway/internal/api/firewall.go`, the whole
`/orgs/:id/nodes/:nodeId/firewall/rules` surface) therefore **never reach a
Shield node**. Sentinel has the translation
(`internal/sentinel/policy/policy.go:114-145`); Shield has none.

- Implement `syncShield` properly: map rules to AdGuard custom rules via
  `POST /control/filtering/set_rules` — `block`/`domain_block` →
  `||domain^`, `wildcard_domain_block` → `||domain^` on the stripped wildcard,
  `allow`/`domain_allow` → `@@||domain^`, `rewrite`/`dns_rewrite` → the
  `/control/rewrite/add` API. Apply `p.Upstreams` through the existing
  `/control/dns_config` path. Mirror the Sentinel switch so the two providers
  cannot drift.
- Extend `ConfigureAdmin` to seed default blocklists via
  `/control/filtering/add_url` on first configure, so a Shield node with no org
  rules still blocks malware/ads out of the box.
- `internal/firewall/client_test.go` already exists — extend it with a fake
  AdGuard that asserts the emitted rule text per rule type.

### DoH in two surfaces

**(i) In-tunnel DoH — ships through the bundle, no app update.**
sing-box accepts `https://host/dns-query` as a DNS server address, and the app
passes `bundle.dns` straight into `_dnsConfig`. So a Shield node that sets
`WG_DNS` to its own DoH URL upgrades existing clients with no release. Serve it
from the node's Gin server (`internal/api/server.go`) as RFC 8484
`/api/v2/dns-query`, forwarding to `cfg.FirewallDNSAddr` — `miekg/dns` is
already a dependency and `internal/dns/forwarder.go` has the exchange logic to
lift into a helper. TLS inside the tunnel can use the existing self-signed cert
from `internal/stealth/tlscert.go`.
**Verify before committing:** the pinned sing-box 1.11.15 rejects unknown DNS
fields at decode, so run the DoH-server variant through
`bin/sing-box/<os>/sing-box check` first (the note at `vpn_models.dart:833`
exists for exactly this reason).

**(ii) Public DoH for unmanaged devices — org policy everywhere.**
Terminate at the gateway, not per node: `/api/v2/doh/:key` proxying to the org's
Shield node over the node API the gateway already authenticates with PASETO (add
`POST /api/v2/dns-query` to the node's `authed` group). Why: the gateway has a
real cert, the key in the path selects the org policy, and no node needs ACME or
a hostname. Two things to get right — the key must be a dedicated revocable
low-privilege DNS key (extend the `store.APIKeyScope*` set) because it will land
in access logs, so disable path logging on that route; and **Android's "Private
DNS" field is DoT, not DoH**, so expose DoT too or scope the Android story to
Chrome. iOS/macOS take a DoH configuration profile happily.

**(iii) ODoH — the thing that earns the claim.**
Gateway as the ODoH *relay*, Shield node as the *target* publishing its key
config: the relay sees who you are but not what you asked; the target sees the
query but not who asked. Needs `application/oblivious-dns-message` handling and
key material in the node's settings store (same pattern as
`internal/stealth/secrets.go` — no env var). Stage it after (i) and (ii); it is
the headline for the positioning, not the first commit.

---

## Track 5 — On-chain registry (Ethereum + Solana only)

Full design: `erebrus-gateway/docs/ZTA_PLAN.md` §T5 and `erebrus/docs/ZTA_PLAN.md` §T5.

The scaffolding is already there and was built for this: `erebrus`'s
`internal/registrar` defines the `Registrar` interface and **froze the
`NodeIdentity` payload** for exactly this moment, `CHAIN_REGISTRATION` (`off |
solana`) is already read from config, the node wallet already signs on both
chains, and the gateway's `internal/wallet` deliberately supports EVM + Solana
only. Nothing about this track is greenfield.

**What goes on chain matters more than that it does.**

| Data | On chain | Why |
| --- | --- | --- |
| Node identity — peer id, DID, IP-**hash**, region, operator wallet, status | yes | public, verifiable, outlives the gateway |
| Subscription expiry, keyed by org id | yes | a node can verify entitlement with no gateway — the actual resilience win, within the limit below |
| Per-session connectivity | no | thousands of writes, zero value; commit per-epoch merkle roots of signed uptime attestations instead |
| User identity, email, device names, configs | never | it is a public ledger, permanently |

**The offline entitlement story has a hard boundary.** Entitlement here is
organization-only — the code says so in four places — so the on-chain record is
keyed by org id, not by wallet. A self-serve org whose owner is the connecting
user can therefore be verified from chain alone; a multi-seat business org cannot,
because that would mean publishing workspace membership, which the table above
rules out permanently. Seat entitlement stays gateway-only, and the client must
say so rather than silently failing for business users.

Three deliberate calls:

- **Operators never pay gas.** The node signs its identity payload; the gateway
  submits as fee payer (Solana `feePayer`, an EVM relayer EOA). Making operators
  fund a wallet before joining would be the worst onboarding regression we could
  ship.
- **A `PaymentRouter` contract on EVM**, because EVM has no memo field and the
  alternatives (CREATE2 deposit addresses, HD-derived receivers) are far more
  moving parts. Solana needs no router — the Solana Pay `reference` pubkey is the
  native primitive for exactly this.
- **The subscription write rides the payment transaction**, so an on-chain
  subscription costs no extra gas.

Contract addresses live in a `chain_contracts` table, not env vars. Contracts
themselves live in `contracts/` on the gateway branch (`evm` Foundry, `solana`
Anchor), kept semantically identical.

## Track 6 — Agent egress over MCP

Full design: `erebrus-mcp/docs/ZTA_PLAN.md`, with the gateway's side in
`erebrus-gateway/docs/ZTA_PLAN.md` §T6.

`erebrus-mcp` today is **control plane only**: it authenticates agents, creates
orgs, mints API keys, registers nodes and provisions VPN clients — then hands the
agent a config and stops. The agent still has to bring its own WireGuard, which
no agent has. That gap is the whole track.

Give it a data plane, in two modes:

- **Proxy mode** — the MCP server runs a bundled sing-box in proxy-only mode
  (exactly what this repo's `SingboxConfigBuilder.build(..., useSystemTunnel:
  false)` already emits: a `mixed` inbound on 127.0.0.1) and returns a local
  proxy URL. Tools: `vpn_egress_start({region | node_id, two_hop})`,
  `vpn_egress_status`, `vpn_egress_stop`. Works for anything that honours
  `HTTPS_PROXY` — most HTTP clients, Playwright, curl.
- **Fetch mode** — `erebrus_fetch({url, method, headers, body, region})` performs
  the request through the tunnel inside the MCP server. This is the one that
  delivers geofenced access with *zero* agent configuration, and it is what most
  agents will actually use.

Be precise about what this hides: the agent is hidden from the **destination**.
The node still sees the MCP host's IP — unless the egress runs two-hop, which is
why `vpn_egress_start` takes a `two_hop` flag. T2 and T6 compose, and that
composition is the honest version of "agents without IP exposure".

**Ship the abuse controls with the feature, not after.** Agent egress attracts
scraping and credential stuffing. Per-org egress quotas in `org_entitlements`,
enforced at provision time, plus the existing `access_revocation` path so one
call kills an agent across every node it touched.

## Track 7 — USDC subscriptions alongside fiat

Full design: `erebrus-gateway/docs/ZTA_PLAN.md` §T7; app UI in
`docs/ZTA_HANDOVER.md` §T7.

Dodo is a recurring-charge provider. Crypto cannot auto-charge, so crypto is a
**prepaid term**: pay once, entitled for N days. That is not a compromise — it
maps exactly onto `billing.AccessDecision{Plan, Until}` and
`org_entitlements.paid_access_until`, which already exist. One entitlement
ledger, two funding sources. Do not emulate recurring billing on chain.

**USDC only, on both chains — not "USDC first".** There is no native-token path
and no price oracle anywhere in this design. One accepted asset per chain removes
the Pyth/Chainlink dependency, the expiring quote, the volatility refund policy
and the per-asset decimals table in one stroke. USDC is 1:1 with USD and 6
decimals on both chains, so the amount is arithmetic, not a quote, and a payment
that lands late is still exactly right.

The agent angle is the strategic one: an agent with a wallet can create an org,
create a payment intent, pay from its own funds, and provision egress with no
human in the loop. That requires only that the intent endpoint accept an **org
API key** as well as a user bearer token. Watch x402 as the eventual front door —
the intent endpoint is deliberately shaped close to it.

## Cleanup — retiring NFT gating

Decided alongside these tracks, and it costs almost nothing: **NFT gating
already grants no access.** `erebrus-gateway/internal/api/subscriptions.go:236`
states it outright — product access is organization-only, and the endpoint
survives only to keep a once-a-month XP award flowing. So there is no entitlement
to grandfather, no access to migrate, and no user who loses a plan.

What it removes: a Go package, a database table, a route, three env vars, three
platform settings, and an app flow that still *advertises* a 30-day NFT grant the
gateway stopped issuing. The app's `kNftEntitlementDays = 30`
(`lib/vpn/gateway_config.dart:29`) documents a grant that cannot happen — this is
a correctness fix wearing a deprecation's clothes.

What stays: already-awarded XP in `xp_claims` (deleting it would retroactively
demote tiers), and the unrelated `"nft"` perk type in `perks.go`. The one thing
to decide rather than drift into: whether `xp_tier_thresholds` should move now
that a 50 XP/month input is gone.

Per-repo detail: `erebrus-gateway/docs/ZTA_PLAN.md` §Cleanup and
`erebrus-vpn/docs/ZTA_HANDOVER.md` §Cleanup.

## Sequencing

0. **Retire NFT gating** — subtracts before anything is added, and leaves one
   unambiguous RPC setting per chain for T5 and T7 to build on.
1. **T1a + T4 org policy** — days, no new surface area, immediate value.
   `allowBackup=false` and a working `syncShield` are both embarrassing-if-asked gaps.
2. **T1b** — the disguise (icon + name). Self-contained in the app.
3. **T2** — the marquee feature, and cheaper than it looks: client-side only.
4. **T7 crypto subscriptions** — self-contained, demanded, and no chain writes
   are needed to start (watch, confirm, credit).
5. **T4 DoH (i)+(ii)** — then ODoH.
6. **T6 agent egress** — once T2 exists, so `two_hop` is real on day one.
7. **T3** — most moving parts (three repos, a frozen protocol, a signed
   distribution channel). Ship the failure-classification and the manual
   "Can't sign in?" path early; the rest can follow.
8. **T5 on-chain** — indexing first, sponsored registration second, subscription
   mirroring last. It is the deepest track and the least urgent, because every
   other track degrades gracefully without it.
