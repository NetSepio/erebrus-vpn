# Zero-Trust Architecture — client app handover (`feat/zta-plan`)

Work order for the Flutter client. Design rationale and the cross-repo picture
live in `docs/ZERO_TRUST_PLAN.md`; the other work orders are
`erebrus-gateway/docs/ZTA_PLAN.md`, `erebrus/docs/ZTA_PLAN.md` and
`erebrus-mcp/docs/ZTA_PLAN.md`, all on the same branch name.

Seven tracks. Four need app work, three barely touch it:

| Track | App work |
| --- | --- |
| T1 App disguise | **All of it** — this is an app-only track |
| T2 Two-hop | **All of it** — client-side only; no node or gateway change |
| T3 Gateway reachability | Failure classification + bootstrap escalation |
| T4 Shield DoH / org policy | One validation task, otherwise node-side |
| T5 On-chain registry | Entitlement fallback + verified-node badge |
| T6 Agent egress (MCP) | None — but keep the config builder portable |
| T7 USDC subscriptions | "Pay with USDC" using wallets we already have |

Nothing here needs a new `--dart-define` or `.env` key.

---

## T1 — App disguise

Covered in full in `docs/ZERO_TRUST_PLAN.md` §Track 1. Summary of the surface:

- `android/app/src/main/AndroidManifest.xml` — launcher intent-filter moves onto
  `<activity-alias>` entries; `allowBackup=false`; cleartext narrowed to
  loopback.
- `android/app/src/main/kotlin/com/erebrus/vpn/AppDisguise.kt` — new; methods on
  the existing `com.erebrus.vpn/methods` channel.
- `ErebrusVpnService.kt` — notification copy from the active profile.
- `lib/settings/disguise_profile.dart`, UI in
  `lib/view/settings/privacy_view.dart`.
- `test/disguise_profile_test.dart` — manifest aliases and Dart profiles must
  match exactly.

PIN and duress PIN are **out of scope** by decision; see the deferral note in the
plan for what that leaves unprotected.

---

## T2 — Two-hop

The marquee feature and cheaper than it looks: the node already forwards and
masquerades the whole client subnet, so hop 2 is just a nested endpoint.

**`lib/vpn/vpn_models.dart`** — `SingboxConfigBuilder.buildTwoHop(...)`:

- Two `endpoints`: `wg-entry` (peer = entry node; `detour` = the carrier tag when
  hop 1 is stealth) and `wg-exit` (peer = exit node, `detour: 'wg-entry'`).
  `route.final = 'wg-exit'`.
- **The direct bypass applies to the entry host only.** `_localRouteRules`
  currently takes a single `wgServerHost`; a bypass for the exit host sends hop 2
  around hop 1 and silently degrades to single-hop with no visible symptom.
  Assert it in a test, not in review.
- MTU ladder: entry 1280, exit 1200. `_buildDirectWireGuard` hardcodes 1280 —
  parameterise it.
- Pre-resolve both peers through `resolveDialHosts`; pass the exit peer as an IP
  literal, since a hostname there would need DNS before hop 2 exists.
- `_dnsConfig`: `dns-remote` detours `wg-exit`; `dns-direct` bootstraps the entry
  carrier host only.

**`lib/vpn/vpn_controller.dart`**

- Do **not** add a fourth `ConnectMode` — it multiplies the transport matrix.
  Add `twoHop` (bool) + `entryNode` to controller state.
- Transports per hop: stealth on hop 1 (that is what beats DPI), plain WireGuard
  on hop 2 (keeps overhead sane).
- Provision twice with the existing `provisionClient`. Gateway rows are keyed by
  (user, node, wg_public_key), so two nodes give two rows with no gateway work.
- Generate a **separate exit keypair** (`erebrus_wg_private_hop2`) rather than
  reusing the single stored key.

**`lib/vpn/vpn_session_store.dart`** — persist `entry_node_id` / `exit_node_id`
so a process restart rebuilds the right UI.

**`lib/view/home/server_sheet.dart`** — enforce
`entry.org.slug != exit.org.slug`. Different operators per hop is the entire
claim; same-operator two-hop is just latency. `VpnNodeOrg` already arrives on
every node, so this costs nothing.

**Tests** — `test/vpn_two_hop_config_test.dart` (endpoint graph, detour chain,
exactly one direct bypass, MTU ladder) plus a case in
`test/singbox_runtime_integration_test.dart` so the bundled `sing-box check`
validates it. That suite skips on macOS; simulate Linux before tagging a release.

---

## T3 — Reachability under blocking

**Classify the failure first.** `GatewayHttp.isTransientNetworkError`
(`lib/vpn/gateway_http.dart`) lumps DNS failure together with reachability
failure. Only the second should escalate:

- DNS failure → already handled by the DoH fallback.
- **Reachability** failure → TLS reset after ClientHello, or a connect timeout to
  an address that resolved fine. That is IP/SNI blocking.

Put the classifier in `lib/vpn/gateway_errors.dart` next to the existing error
envelope parsing, and add a test with both shapes.

**`lib/vpn/bootstrap_config.dart`** (new) — compile-time default descriptors in
code, plus a secure-storage cache refreshed from `GET /api/v2/bootstrap` whenever
the gateway *is* reachable. Verify the gateway's Ed25519 signature before
caching; the verify key comes from `GET /api/v2/capabilities`.

**Out-of-band import** — accept a signed `erebrusvpn://bootstrap?…` payload
through the existing deep-link handler (`lib/auth/deep_link_handler.dart`) and QR
scanner (`lib/view/guest/guest_scan_view.dart`). A screenshot in a group chat is
the distribution channel that actually survives a national shutdown, and the
pieces are already built.

**`lib/vpn/bootstrap_tunnel.dart`** (new)

- *Desktop*: run the engine proxy-only (`useSystemTunnel: false` already yields
  the `mixed-in` inbound on 127.0.0.1:10808) and point the gateway client at it
  with `HttpClient.findProxy`. Heed the existing warning at
  `lib/vpn/gateway_http.dart:20` — `findProxy`, never `connectionFactory`, which
  breaks SNI.
- *Mobile*: `ErebrusVpnService` always establishes a TUN, so v1 is a short-lived
  real tunnel to the bootstrap node (reuse `_connectTo` with a synthetic bundle),
  used for sign-in/discovery, then reconnect to the chosen node. One visible
  connect/disconnect cycle, no new native code. A no-TUN libbox path in
  `SingboxBridge.kt` is the follow-up, not the blocker.

**Make it manual-first.** A "Can't sign in?" action in the login view that the
user taps, before any automatic escalation. An auto-fallback that misfires on a
flaky café network is a support nightmare.

---

## T4 — Shield DoH

Almost entirely node-side, but one task is ours and it gates the whole design:

sing-box accepts `https://host/dns-query` as a DNS server address, and the app
passes `bundle.dns` straight into `_dnsConfig`, so a Shield node can upgrade
existing clients with no app release. **Before the node team ships a node that
advertises a DoH URL**, validate the resulting config against the pinned
1.11.15 with `bin/sing-box/<os>/sing-box check` — that build rejects unknown DNS
fields at decode (see the note at `lib/vpn/vpn_models.dart:833`), and confirm how
it wants a self-signed in-tunnel cert expressed. Report back either way; the node
work order has a fallback if it is awkward.

Add the case to `test/singbox_runtime_integration_test.dart` so it stays true.

---

## T5 — On-chain registry

Two app-visible pieces, both small, both good for the story:

- **Verified node badge.** Once the indexer mirrors `NodeRegistry` events,
  `GET /api/v2/nodes` carries `onchain_registered_at`. Parse it in
  `VpnNode.fromJson` (`lib/vpn/vpn_models.dart`) and render a badge in
  `lib/view/home/node_display.dart` next to the existing org-verified chip. Keep
  the two visually distinct: org-verified is "we checked the operator",
  on-chain is "the node's identity is publicly attested".
- **Entitlement fallback, with a boundary to respect.** `SubscriptionRegistry`
  maps **org id** → (plan, expiry) on chain, not wallet → plan: entitlement in
  this product is organization-only. So the offline check works for a self-serve
  org whose owner is the signed-in wallet, and **cannot** work for a multi-seat
  business org, because member→org mapping would mean publishing workspace
  membership. Build the fallback for the personal case and show business users an
  honest "can't verify your plan offline" state rather than a silent failure.
  This pairs with T3: bootstrap gets you a *node*, on-chain entitlement proves
  you are *allowed* to use it, and neither needs the gateway to be up.
  - `lib/auth/entitlement_state.dart` — `source` is already a free-form string
    (`trial | nft | plan | admin | rank`), so adding `onchain` is additive and
    old builds tolerate it.
  - Keep the RPC read behind the same DoH/bootstrap-aware HTTP path, or a blocked
    RPC endpoint just moves the problem.

---

## T6 — Agent egress

No app work. One thing to protect, though: the MCP server
(`erebrus-mcp/docs/ZTA_PLAN.md`)
needs the same proxy-mode sing-box config this app builds. Rather than letting a
TypeScript copy of `SingboxConfigBuilder` drift from the Dart one, keep
`build(..., useSystemTunnel: false)` output stable and documented, and treat
`test/vpn_config_test.dart` as the shared contract. If the two implementations
diverge, the symptom will be an agent that silently leaks its own IP.

---

## T7 — USDC subscriptions

The app already holds both wallet stacks: Reown AppKit for EVM
(`lib/view/auth/reown_host.dart`) and Solana Mobile Wallet Adapter
(`lib/auth/solana_mobile_wallet.dart`). Paying is a transfer those can sign.

- `lib/auth/gateway_auth_client.dart` / a new `lib/billing/crypto_intent.dart` —
  `POST /api/v2/orgs/:id/billing/crypto/intent`, then poll
  `GET …/crypto/intent/:id` for `pending → confirming → settled`.
- UI in `lib/view/settings/account_sheets.dart` next to the existing plan
  display: "Pay with USDC", a network picker (Ethereum / Solana — that is the
  only choice the user makes), the amount, a copyable address **and** a wallet
  hand-off, then a waiting state driven by the poll.
- **USDC only, both chains, no native ETH/SOL.** The amount is USD × 1, so the
  UI should not imply a quote: no "rate expires in…" copy, no refresh button.
  The 20-minute countdown is the *intent* expiring, not a price — word it as
  "this payment request expires in 19:42", and a payment that lands late is
  still the right amount, so the recovery path is "we'll credit it", not
  "you underpaid".
- Entitlement arrives through the existing `GET /api/v2/subscriptions` path with
  `source: "onchain"`; `EntitlementState` needs no structural change, but
  `lib/plan_label.dart` and the account sheet copy should not assume a Dodo
  subscription exists (a crypto-funded org has `paid_access_until` and no
  provider subscription id).
- Do not build in-app purchase alongside this. App Store rules on crypto
  purchases of digital services are a separate fight; keep the payment path a
  web/wallet hand-off and check the current policy before shipping on iOS.

---

## Cleanup — remove NFT gating from the app

Retired across the stack this branch (gateway detail in
`erebrus-gateway/docs/ZTA_PLAN.md` §Cleanup). On the app side this **fixes a live
mismatch rather than removing a feature**: the gateway stopped granting NFT
entitlement some time ago (`internal/api/subscriptions.go:236` — "no longer
grants a personal NFT entitlement"), while the app still advertises one.

- `lib/vpn/gateway_config.dart:28-29` — delete `kNftEntitlementDays = 30`. The
  grant it documents does not exist.
- `lib/auth/gateway_auth_client.dart:300-314` — delete `refreshNftEntitlement`.
  Its doc comment ("verify gating NFT, grant ~30d") describes behaviour the
  gateway removed, and it hardcodes `'nft_gating': true` into the parsed result.
- `lib/auth/wallet_auth_controller.dart:126,1032-1052` — delete
  `isRefreshingNft` and `refreshNftEntitlement`, including the
  "NFT gating is not enabled on this gateway" error string.
- `lib/auth/entitlement_state.dart:12,26,55` — drop `nftGatingEnabled` and the
  `nft_gating` parse. Leave `'nft'` in the `source` doc comment only if the
  gateway can still return it; it cannot, so remove it there too.
- `lib/view/settings/settings_view.dart:933,937` — remove the refresh-NFT busy
  state and the `'nft' => 'NFT'` source label.
- `test/entitlement_state_test.dart:9,13` — drop the `nft_gating` assertions.

Ship this **after** the gateway returns 410 on the endpoint, not before, so an
app build in the wild never calls a route that has already vanished.

## Suggested order

0. **Cleanup** — the NFT removal, once the gateway's 410 is live. It is small and
   it stops the app promising an entitlement nobody can get.
1. **T1** — self-contained, visible, no cross-repo coordination.
2. **T2** — the feature users will notice; needs nobody else.
3. **T4** validation task (it unblocks the node team).
4. **T7** app UI, once the gateway intent endpoint is live.
5. **T3** classifier + manual "Can't sign in?", then the bootstrap tunnel.
6. **T5** badge and entitlement fallback, last — it needs the indexer.
