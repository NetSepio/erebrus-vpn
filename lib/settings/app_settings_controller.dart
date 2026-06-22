import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/platform_capabilities.dart';
import '../vpn/vpn_controller.dart';
import '../vpn/vpn_models.dart';

/// Persisted user preferences (protocol default, kill switch, diagnostics).
class AppSettingsController extends GetxController {
  static const _kDefaultProtocol = 'settings.default_protocol';
  static const _kAutoConnect = 'settings.auto_connect';
  static const _kKillSwitch = 'settings.kill_switch';
  static const _kDiagnostics = 'settings.anonymous_diagnostics';
  static const _kOnboardingSeen = 'settings.onboarding_seen';

  final defaultProtocol = ConnectMode.auto.obs;
  final autoConnectOnLaunch = false.obs;
  final killSwitchEnabled = true.obs;
  final anonymousDiagnostics = false.obs;

  /// Whether first-launch onboarding has been completed (persisted).
  final onboardingSeen = false.obs;

  final diagnosticsStatus = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    defaultProtocol.value = _parseMode(prefs.getString(_kDefaultProtocol));
    autoConnectOnLaunch.value = prefs.getBool(_kAutoConnect) ?? false;
    killSwitchEnabled.value = prefs.getBool(_kKillSwitch) ?? true;
    anonymousDiagnostics.value = prefs.getBool(_kDiagnostics) ?? false;
    onboardingSeen.value = prefs.getBool(_kOnboardingSeen) ?? false;

    if (Get.isRegistered<VpnController>()) {
      Get.find<VpnController>().setMode(defaultProtocol.value);
    }
    debugPrint('[Settings] loaded default=${defaultProtocol.value.label} killSwitch=${killSwitchEnabled.value}');
  }

  Future<void> setDefaultProtocol(ConnectMode mode) async {
    defaultProtocol.value = mode;
    if (Get.isRegistered<VpnController>()) {
      Get.find<VpnController>().setMode(mode);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultProtocol, mode.name);
  }

  Future<void> markOnboardingSeen() async {
    if (onboardingSeen.value) return;
    onboardingSeen.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSeen, true);
  }

  Future<void> setAutoConnect(bool value) async {
    autoConnectOnLaunch.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoConnect, value);
  }

  Future<void> setKillSwitch(bool value) async {
    killSwitchEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKillSwitch, value);
    if (!value && Get.isRegistered<VpnController>()) {
      await Get.find<VpnController>().releaseKillSwitchIfActive();
    }
  }

  Future<void> setAnonymousDiagnostics(bool value) async {
    anonymousDiagnostics.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDiagnostics, value);
    if (value) {
      _sendMockDiagnostic('opt-in', vpn: _vpnOrNull());
    } else {
      diagnosticsStatus.value = null;
    }
  }

  VpnController? _vpnOrNull() =>
      Get.isRegistered<VpnController>() ? Get.find<VpnController>() : null;

  /// Mock telemetry — Dart-only, works on Android/iOS/macOS/Windows/Linux.
  /// No network call yet; logs locally when enabled.
  void _sendMockDiagnostic(String event, {VpnController? vpn}) {
    if (!anonymousDiagnostics.value) return;
    final v = vpn ?? _vpnOrNull();
    final node = v?.selectedNode.value;
    final payload = <String, dynamic>{
      'event': event,
      'platform': PlatformCapabilities.platformLabel,
      'os': defaultTargetPlatform.name,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'default_protocol': defaultProtocol.value.name,
      if (v != null) ...{
        'vpn_stage': v.stage.value.name,
        'active_transport': v.activeTransport.value?.name,
        'kill_switch': v.killSwitchBlocking.value,
        if (node != null) ...{
          'node_id': node.id,
          'node_region': node.region,
        },
      },
    };
    debugPrint('[Diagnostics] mock upload: $payload');
    final ping = DateTime.now().toLocal().toString().substring(11, 19);
    final region = node?.region;
    diagnosticsStatus.value = region == null || region.isEmpty
        ? 'Last mock ping: $ping · ${PlatformCapabilities.platformLabel}'
        : 'Last mock ping: $ping · $region · ${PlatformCapabilities.platformLabel}';
  }

  void pingDiagnosticsIfEnabled({VpnController? vpn}) {
    if (anonymousDiagnostics.value) _sendMockDiagnostic('heartbeat', vpn: vpn);
  }

  static ConnectMode _parseMode(String? raw) => switch (raw) {
        'stealth' => ConnectMode.stealth,
        'wireguard' => ConnectMode.wireguard,
        _ => ConnectMode.auto,
      };
}