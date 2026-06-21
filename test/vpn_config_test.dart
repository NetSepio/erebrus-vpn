import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:erebrus_vpn/vpn/vpn_models.dart';

// A minimal node-style credential bundle: a sing-box profile with the WG
// endpoint + both carrier outbounds (as the gateway/node returns).
const _bundleJson = '''
{
  "wireguard": {
    "server_public_key": "6RfVDGZnJs4BJSzRk+iR8Ta1ftSMSnEC5fGwSbw7RkM=",
    "endpoint": "203.0.113.10:51820",
    "address": "10.0.0.7/32",
    "dns": "1.1.1.1"
  },
  "vless_uri": "vless://uuid@203.0.113.10:8443?security=reality#node",
  "hysteria2_uri": "hysteria2://pw@203.0.113.10:4443?#node",
  "singbox_profile": {
    "endpoints": [
      {"type":"wireguard","tag":"wg-out","address":["10.0.0.7/32"],
       "private_key":"REPLACE_WITH_CLIENT_PRIVATE_KEY",
       "peers":[{"address":"127.0.0.1","port":51820,"public_key":"srv","allowed_ips":["0.0.0.0/0"]}],
       "detour":"carrier-vless"}
    ],
    "outbounds": [
      {"type":"vless","tag":"carrier-vless","server":"203.0.113.10","server_port":8443},
      {"type":"hysteria2","tag":"carrier-hysteria2","server":"203.0.113.10","server_port":4443}
    ],
    "route": {"final": "wg-out"}
  }
}
''';

void main() {
  test('ConnectMode maps to the right transport fallback order', () {
    expect(ConnectMode.auto.transports,
        [Transport.wireguard, Transport.vlessReality, Transport.hysteria2]);
    expect(ConnectMode.stealth.transports, [Transport.vlessReality, Transport.hysteria2]);
    expect(ConnectMode.wireguard.transports, [Transport.wireguard]);
  });

  test('CredentialBundle parses the node response', () {
    final b = CredentialBundle.fromJson(jsonDecode(_bundleJson));
    expect(b.serverPublicKey, '6RfVDGZnJs4BJSzRk+iR8Ta1ftSMSnEC5fGwSbw7RkM=');
    expect(b.endpoint, '203.0.113.10:51820');
    expect(b.hasStealth, isTrue);
  });

  test('WireGuard transport dials the real endpoint, no carrier detour', () {
    final b = CredentialBundle.fromJson(jsonDecode(_bundleJson));
    final cfg = SingboxConfigBuilder.build(
        bundle: b, transport: Transport.wireguard, clientPrivateKey: 'PRIV');
    final ep = (cfg['endpoints'] as List).first as Map;
    expect(ep['private_key'], 'PRIV');
    expect(ep.containsKey('detour'), isFalse);
    final peer = (ep['peers'] as List).first as Map;
    expect(peer['address'], '203.0.113.10');
    expect(peer['port'], 51820);
    expect((cfg['inbounds'] as List).first['type'], 'tun');
    expect((cfg['inbounds'] as List).first['stack'], 'gvisor');
    expect((cfg['dns'] as Map)['final'], 'dns-remote');
    expect((cfg['route'] as Map)['auto_detect_interface'], isFalse);
  });

  test('Stealth transport detours WG through the VLESS carrier (loopback peer)', () {
    final b = CredentialBundle.fromJson(jsonDecode(_bundleJson));
    final cfg = SingboxConfigBuilder.build(
        bundle: b, transport: Transport.vlessReality, clientPrivateKey: 'PRIV');
    final ep = (cfg['endpoints'] as List).first as Map;
    expect(ep['detour'], 'carrier-vless');
    final peer = (ep['peers'] as List).first as Map;
    expect(peer['address'], '127.0.0.1'); // node de-wraps and forwards locally
    expect(cfg['route']['final'], 'wg-out');
  });
}
