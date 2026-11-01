import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erebrus_vpn/view/home/server_sheet.dart';
import 'package:erebrus_vpn/vpn/gateway_client.dart';
import 'package:erebrus_vpn/vpn/gateway_controller.dart';
import 'package:erebrus_vpn/vpn/node_probe.dart';
import 'package:erebrus_vpn/vpn/singbox_engine.dart';
import 'package:erebrus_vpn/vpn/vpn_controller.dart';
import 'package:erebrus_vpn/vpn/vpn_models.dart';

class _IdleEngine implements SingboxEngine {
  @override
  Stream<VpnStage> get onStage => const Stream.empty();
  @override
  Stream<VpnStats> get onStats => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGatewayClient extends GatewayClient {
  _FakeGatewayClient({required this.public, this.orgs = const []})
    : super(baseUrl: 'https://gateway.test');

  final List<VpnNode> public;
  final List<VpnOrg> orgs;

  @override
  Future<List<VpnNode>> fetchNodes() async => public;
  @override
  Future<List<VpnOrg>> fetchOrgs() async => orgs;
  @override
  Future<List<VpnNode>> fetchOrgNodes() async => const [];
}

const _acme = VpnNodeOrg(name: 'Acme', slug: 'acme');

VpnNode _node(
  String id, {
  bool? accepting,
  String access = 'public',
  VpnNodeOrg? org,
}) => VpnNode(
  id: id,
  name: id,
  region: 'US',
  did: '',
  protocols: const ['wireguard'],
  loadPct: 10,
  accessMode: access,
  org: org,
  acceptingClients: accepting,
);

void main() {
  group('pickerTabFor', () {
    test('a public node run by an org opens the Public tab', () {
      final node = _node('us', org: _acme);
      final tab = pickerTabFor(node, publicNodes: [node], orgNodes: const []);
      expect(tab.tab, 0);
      expect(tab.orgSlug, isNull);
    });

    test('an org node opens the Private tab on its org', () {
      final node = _node('priv', access: 'private', org: _acme);
      final tab = pickerTabFor(node, publicNodes: const [], orgNodes: [node]);
      expect(tab.tab, 1);
      expect(tab.orgSlug, 'acme');
    });

    test('no selection opens the Public tab', () {
      expect(
        pickerTabFor(null, publicNodes: const [], orgNodes: const []).tab,
        0,
      );
    });
  });

  group('NodeProbe', () {
    setUp(NodeProbe.resetForTesting);

    final node = VpnNode.fromJson({
      'node_id': 'is',
      'endpoints': {
        'wireguard': {'host': '192.0.2.10', 'port': 51820},
      },
    });

    test('keeps pings measured outside the tunnel while it is up', () async {
      final direct = await NodeProbe.probeAll([node], probe: (_) async => 250);
      expect(direct, {'is': 250});

      var probed = false;
      final whileUp = await NodeProbe.probeAll(
        [node],
        tunnelActive: true,
        probe: (_) async {
          probed = true;
          return 9;
        },
      );
      expect(probed, isFalse);
      expect(whileUp, {'is': 250});
    });

    test(
      'shows no ping while the tunnel is up and none was measured',
      () async {
        final whileUp = await NodeProbe.probeAll(
          [node],
          tunnelActive: true,
          probe: (_) async => 9,
        );
        expect(whileUp, isEmpty);
      },
    );
  });

  group('server sheet', () {
    late GatewayController gateway;
    late VpnController vpn;

    Future<void> openSheet(
      WidgetTester tester, {
      required List<VpnNode> public,
      List<VpnOrg> orgs = const [],
      VpnNode? selected,
    }) async {
      SharedPreferences.setMockInitialValues({});
      Get.testMode = true;
      vpn = Get.put(VpnController(engine: _IdleEngine()));
      gateway = Get.put(
        GatewayController(
          client: _FakeGatewayClient(public: public, orgs: orgs),
        ),
      );
      await gateway.refreshNodes();
      vpn.selectNode(selected ?? public.first);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showServerSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> closeSheet(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      gateway.onClose();
      vpn.onClose();
      Get.reset();
    }

    testWidgets('a full node is marked and cannot be picked', (tester) async {
      final home = _node('Home');
      final full = _node('ELS-Sweden', accepting: false);
      await openSheet(tester, public: [home, full], selected: home);
      try {
        expect(find.text('Full'), findsOneWidget);
        await tester.tap(find.text('ELS-Sweden'));
        await tester.pumpAndSettle();
        // Sheet still open, selection unchanged, nothing torn down.
        expect(find.text('Select node'), findsOneWidget);
        expect(vpn.selectedNode.value?.id, 'Home');
        expect(vpn.stage.value, VpnStage.disconnected);
      } finally {
        await closeSheet(tester);
      }
    });

    testWidgets(
      'opens on Public when the current public node belongs to an empty org',
      (tester) async {
        final current = _node('ORB-US', org: _acme);
        await openSheet(
          tester,
          public: [current],
          orgs: const [VpnOrg(name: 'Acme', slug: 'acme')],
          selected: current,
        );
        try {
          expect(find.textContaining('ORB-US'), findsOneWidget);
          expect(find.textContaining('No nodes in'), findsNothing);
        } finally {
          await closeSheet(tester);
        }
      },
    );
  });
}
