import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'singbox_engine.dart';

/// Polls sing-box's Clash API `/traffic` SSE stream for live counters.
/// Used by the desktop sing-box CLI subprocess (same endpoint on all platforms
/// when `experimental.clash_api` is enabled in the config).
class ClashStatsPoller {
  ClashStatsPoller({this.baseUrl = 'http://127.0.0.1:9090'});

  final String baseUrl;
  String? secret;
  final _ctrl = StreamController<VpnStats>.broadcast();

  HttpClient? _client;
  StreamSubscription<String>? _sub;
  int _rxTotal = 0;
  int _txTotal = 0;

  Stream<VpnStats> get stream => _ctrl.stream;

  Future<void> start() async {
    await stop();
    _rxTotal = 0;
    _txTotal = 0;
    _client = HttpClient();
    try {
      final req = await _client!.getUrl(Uri.parse('$baseUrl/traffic'));
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (secret != null && secret!.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${secret!}');
      }
      final res = await req.close();
      if (res.statusCode != 200) {
        debugPrint('[Stats] clash /traffic HTTP ${res.statusCode}');
        return;
      }
      _sub = res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine, onError: (e) => debugPrint('[Stats] clash stream error: $e'));
    } catch (e) {
      debugPrint('[Stats] clash poll failed: $e');
    }
  }

  void _onLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty) return;
    try {
      final j = jsonDecode(payload) as Map<String, dynamic>;
      final up = (j['up'] as num?)?.toInt() ?? 0;
      final down = (j['down'] as num?)?.toInt() ?? 0;
      _txTotal += up;
      _rxTotal += down;
      if (!_ctrl.isClosed) {
        _ctrl.add(VpnStats(
          rxBytes: _rxTotal,
          txBytes: _txTotal,
          uplinkBps: up,
          downlinkBps: down,
        ));
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _client?.close(force: true);
    _client = null;
  }

  void dispose() {
    stop();
    _ctrl.close();
  }
}