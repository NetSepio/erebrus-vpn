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
    this.downloadMbps,
    this.uploadMbps,
    this.orgName,
    this.clientPingMs,
    this.isPlaceholder = false,
    this.showLoad = true,
    this.showNodeSpeedtest = false,
  });

  final String flag;
  final String name;
  final String location;
  final String network;
  final Color networkColor;
  final double loadValue;
  final String access;
  final bool supportsStealth;
  final int minTier;
  final int? latencyMs;
  final double? downloadMbps;
  final double? uploadMbps;
  final String? orgName;
  final int? clientPingMs;
  final bool isPlaceholder;
  final bool showLoad;
  final bool showNodeSpeedtest;

  String get loadLabel => showLoad ? '${loadValue.toStringAsFixed(0)}%' : '—';

  Color get loadColor => isPlaceholder
      ? AppColors.textMuted
      : loadValue < 50
          ? AppColors.success
          : (loadValue < 80 ? AppColors.warn : AppColors.danger);

  String pingLabel({bool probing = false}) {
    final local = clientPingMs;
    if (local != null && local > 0) return '$local';
    if (probing) return '…';
    return '—';
  }

  Color pingColor({bool probing = false}) {
    final local = clientPingMs;
    if (local == null || local <= 0) return probing ? AppColors.textSecondary : AppColors.textMuted;
    if (local < 80) return AppColors.success;
    if (local < 160) return AppColors.warn;
    return AppColors.danger;
  }

  String get nodeUplinkLabel {
    final ms = latencyMs;
    if (ms == null || ms <= 0) return '—';
    return '${ms}ms';
  }

  String get downloadLabel => _mbpsLabel(downloadMbps);

  String get uploadLabel => _mbpsLabel(uploadMbps);

  String get accessLabel => switch (access) {
        'private' => 'Private',
        _ => 'Public',
      };

  Color get accessColor => switch (access) {
        'private' => AppColors.accent,
        _ => AppColors.textMuted,
      };

  String? get tierLabel => minTier > 0 ? 'T$minTier' : null;

  static String _mbpsLabel(double? mbps) {
    if (mbps == null || mbps <= 0) return '—';
    if (mbps >= 100) return '${mbps.toStringAsFixed(0)}';
    if (mbps >= 10) return mbps.toStringAsFixed(1);
    return mbps.toStringAsFixed(2);
  }

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

  static NodeDisplay of(
    VpnNode? node, {
    bool forcePlaceholder = false,
    int? clientPingMs,
  }) {
    if (node == null || forcePlaceholder) return placeholder();
    final region = node.region.isEmpty ? 'Erebrus node' : node.region;
    return NodeDisplay(
      flag: _flag(node.region),
      name: node.name,
      location: region,
      network: node.protocolsLabel,
      networkColor: node.supportsStealth ? AppColors.accent : AppColors.textTertiary,
      loadValue: node.loadPct,
      access: node.accessMode,
      supportsStealth: node.supportsStealth,
      minTier: node.minTier,
      latencyMs: node.latencyMs,
      downloadMbps: node.downloadMbps,
      uploadMbps: node.uploadMbps,
      orgName: node.orgName,
      clientPingMs: clientPingMs,
      showNodeSpeedtest: node.hasReportedSpeedtest,
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