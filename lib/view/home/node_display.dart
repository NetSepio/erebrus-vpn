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

  String get loadLabel => '${loadValue.toStringAsFixed(0)}%';

  Color get loadColor =>
      loadValue < 50 ? AppColors.success : (loadValue < 80 ? AppColors.warn : AppColors.danger);

  String get accessLabel => switch (access) {
        'private' => 'Private',
        _ => 'Public',
      };

  Color get accessColor => switch (access) {
        'private' => AppColors.accent,
        _ => AppColors.textMuted,
      };

  String? get tierLabel => minTier > 0 ? 'T$minTier' : null;

  static NodeDisplay of(VpnNode? node) {
    if (node == null) {
      return const NodeDisplay(
        flag: '🌐',
        name: 'Choose a node',
        location: 'Smart pick by latency',
        network: 'SOL',
        networkColor: AppColors.solana,
        loadValue: 0,
        access: 'public',
        supportsStealth: false,
      );
    }
    final region = node.region.isEmpty ? 'Erebrus node' : node.region;
    final latency = node.latencyMs;
    final location = latency != null ? '$region · ${latency}ms' : region;
    return NodeDisplay(
      flag: _flag(node.region),
      name: node.name,
      location: location,
      network: 'SOL',
      networkColor: AppColors.solana,
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