import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../platform/secure_storage.dart';
import 'guest_config_model.dart';

/// Persists imported guest VPN configs and exposes them as observable state.
class GuestConfigController extends GetxController {
  static const _kKey = 'erebrus.guest_configs.v1';

  final configs = <GuestVpnConfig>[].obs;
  final selectedId = RxnString();

  GuestVpnConfig? get selected {
    if (selectedId.value == null) return null;
    for (final c in configs) {
      if (c.id == selectedId.value) return c;
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void select(GuestVpnConfig? config) {
    selectedId.value = config?.id;
  }

  Future<void> add(GuestVpnConfig config) async {
    configs.add(config);
    select(config);
    await _persist();
  }

  Future<void> delete(GuestVpnConfig config) async {
    configs.removeWhere((c) => c.id == config.id);
    if (selectedId.value == config.id) {
      selectedId.value = configs.isEmpty ? null : configs.first.id;
    }
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= configs.length) return;
    if (newIndex < 0 || newIndex > configs.length) return;
    final item = configs.removeAt(oldIndex);
    configs.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    await _persist();
  }

  Future<void> _load() async {
    try {
      final raw = await ErebrusSecureStorage.read(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final parsed = list
          .map((e) {
            try {
              final map = (e as Map).cast<String, dynamic>();
              return GuestVpnConfig.fromJson(map);
            } catch (err) {
              debugPrint('[GuestConfig] failed to parse entry: $err');
              return null;
            }
          })
          .whereType<GuestVpnConfig>()
          .toList();
      configs.value = parsed;
      if (selectedId.value == null && configs.isNotEmpty) {
        selectedId.value = configs.first.id;
      }
    } catch (e) {
      debugPrint('[GuestConfig] load failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final json = configs.map((c) => c.toJson()).toList();
      await ErebrusSecureStorage.write(_kKey, jsonEncode(json));
    } catch (e) {
      debugPrint('[GuestConfig] persist failed: $e');
    }
  }
}
