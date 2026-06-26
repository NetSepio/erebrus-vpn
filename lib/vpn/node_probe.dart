import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vpn_models.dart';

/// Measures phone → node TCP handshake RTT using discovery endpoint hosts/ports.
class NodeProbe {
  const NodeProbe._();

  static const _probeTimeout = Duration(seconds: 3);
  static const _maxConcurrent = 4;

  static Future<Map<String, int>> probeAll(Iterable<VpnNode> nodes) async {
    if (kIsWeb) return const {};
    final list = nodes.where((n) => n.canProbe).toList(growable: false);
    if (list.isEmpty) return const {};

    final results = <String, int>{};
    for (var i = 0; i < list.length; i += _maxConcurrent) {
      final batch = list.skip(i).take(_maxConcurrent);
      final entries = await Future.wait(
        batch.map((node) async {
          final ms = await probeNode(node);
          return MapEntry(node.id, ms);
        }),
      );
      for (final entry in entries) {
        if (entry.value != null) results[entry.key] = entry.value!;
      }
    }
    return results;
  }

  static Future<int?> probeNode(VpnNode node) async {
    if (kIsWeb || !node.canProbe) return null;
    final host = node.probeHost!;
    for (final port in node.probePorts) {
      final ms = await _tcpRtt(host, port);
      if (ms != null) return ms;
    }
    return null;
  }

  static Future<int?> _tcpRtt(String host, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: _probeTimeout);
      stopwatch.stop();
      await socket.close();
      return stopwatch.elapsedMilliseconds;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on IOException {
      return null;
    } catch (_) {
      return null;
    }
  }
}