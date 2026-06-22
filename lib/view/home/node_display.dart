import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../vpn/vpn_models.dart';

/// Maps a real gateway [VpnNode] onto the fields the design's node UI shows.
///
/// The gateway discovery list (`GET /api/v2/nodes`) currently returns
/// id/name/region/protocols/load — it does not yet carry ping, peer counts, or
/// public/private/shared access scoping. We surface what is real (name, region,
/// load, transport capability) and default the rest (network = Solana, access =
/// public) rather than inventing latency/peer numbers. As the node API grows to
/// match the handoff data model, extend this mapper.
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
  });

  final String flag;
  final String name;
  final String location;
  final String network;
  final Color networkColor;
  final double loadValue;
  final String access; // public | private | shared
  final bool supportsStealth;

  String get loadLabel => '${loadValue.toStringAsFixed(0)}%';

  Color get loadColor =>
      loadValue < 50 ? AppColors.success : (loadValue < 80 ? AppColors.warn : AppColors.danger);

  String get accessLabel => switch (access) {
        'private' => 'Private',
        'shared' => 'Shared',
        _ => 'Public',
      };

  Color get accessColor => switch (access) {
        'private' => AppColors.accent,
        'shared' => AppColors.shared,
        _ => AppColors.textMuted,
      };

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
    return NodeDisplay(
      flag: _flag(node.region),
      name: node.name,
      location: node.region.isEmpty ? 'Erebrus node' : node.region,
      network: 'SOL',
      networkColor: AppColors.solana,
      loadValue: node.loadPct,
      access: 'public',
      supportsStealth: node.supportsStealth,
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
