import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../vpn/vpn_models.dart';

/// Maps a gateway [VpnNode] onto the fields the connect / server picker UI shows.
class NodeDisplay {
  const NodeDisplay({
    required this.flag,
    required this.name,
    required this.location,
    required this.network,
    required this.networkColor,
    required this.loadValue,
    required this.access,
    required this.supportsStealth,
    this.minTier = 0,
    this.latencyMs,
    this.isPlaceholder = false,
    this.showLoad = true,
  });

  final String flag;
  final String name;
  final String location;
  final String network;
  final Color networkColor;
  final double loadValue;
  final String access; // public | private
  final bool supportsStealth;
  final int minTier;
  final int? latencyMs;
  final bool isPlaceholder;
  final bool showLoad;

  String get loadLabel => showLoad ? '${loadValue.toStringAsFixed(0)}%' : '—';

  Color get loadColor => isPlaceholder
      ? AppColors.textMuted
      : loadValue < 50
          ? AppColors.success
          : (loadValue < 80 ? AppColors.warn : AppColors.danger);

  String get accessLabel => switch (access) {
        'private' => 'Private',
        _ => 'Public',
      };

  Color get accessColor => switch (access) {
        'private' => AppColors.accent,
        _ => AppColors.textMuted,
      };

  String? get tierLabel => minTier > 0 ? 'T$minTier' : null;

  /// Connect-tab card when no node is selected or the registry is empty.
  static NodeDisplay placeholder({bool registryError = false}) {
    return NodeDisplay(
      flag: '',
      name: registryError ? 'Registry unavailable' : 'Select a server',
      location: registryError
          ? 'Could not reach the node registry'
          : 'Community nodes on the Erebrus network',
      network: 'DePIN',
      networkColor: AppColors.textMuted,
      loadValue: 0,
      access: 'public',
      supportsStealth: false,
      isPlaceholder: true,
      showLoad: false,
    );
  }

  static NodeDisplay of(VpnNode? node, {bool forcePlaceholder = false}) {
    if (node == null || forcePlaceholder) return placeholder();
    final region = node.region.isEmpty ? 'Erebrus node' : node.region;
    final latency = node.latencyMs;
    final location = latency != null && latency > 0 ? '$region · ${latency}ms' : region;
    return NodeDisplay(
      flag: _flag(node.region),
      name: node.name,
      location: location,
      network: 'WG',
      networkColor: AppColors.accent,
      loadValue: node.loadPct,
      access: node.accessMode,
      supportsStealth: node.supportsStealth,
      minTier: node.minTier,
      latencyMs: latency,
    );
  }

  /// Region code (2-letter ISO) → flag emoji; falls back to a globe.
  static String _flag(String region) {
    final code = region.trim().toUpperCase();
    if (code.length < 2) return '🌐';
    const base = 0x1F1E6;
    final a = code.codeUnitAt(0);
    final b = code.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '🌐';
    return String.fromCharCode(base + a - 65) + String.fromCharCode(base + b - 65);
  }
}