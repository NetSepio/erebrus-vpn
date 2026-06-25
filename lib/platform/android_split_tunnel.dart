import 'package:flutter/services.dart';

/// A user-launchable Android app eligible for split-tunnel bypass.
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  final String packageName;
  final String label;

  factory InstalledApp.fromMap(Map<dynamic, dynamic> m) => InstalledApp(
        packageName: m['package'] as String? ?? '',
        label: m['label'] as String? ?? '',
      );
}

/// Android-only helpers for per-app split tunneling.
class AndroidSplitTunnel {
  AndroidSplitTunnel._();

  static const MethodChannel _method = MethodChannel('dev.erebrus/singbox');

  static Future<List<InstalledApp>> listApps() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('listApps');
      return (raw ?? const [])
          .map((e) => InstalledApp.fromMap((e as Map?) ?? const {}))
          .where((a) => a.packageName.isNotEmpty)
          .toList();
    } on PlatformException {
      return const [];
    }
  }
}