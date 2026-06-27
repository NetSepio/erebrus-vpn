import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../vpn/vpn_models.dart';

/// Maps a gateway [VpnNode] onto the fields the connect / server picker UI shows.
class NodeDisplay {
  const NodeDisplay({
    required this.flag,
    required this.name,
    required this.location,
    required this.regionCompact,
    required this.network,
    required this.networkColor,
    required this.loadValue,
    required this.access,
    required this.supportsStealth,
    this.minTier = 0,
    this.org,
    this.activityTime,
    this.activityLive = false,
    this.showSolanaBadge = false,
    this.downloadMbps,
    this.uploadMbps,
    this.clientPingMs,
    this.isPlaceholder = false,
    this.showLoad = true,
    this.showNodeSpeedtest = false,
    this.showActivity = false,
  });

  final String flag;
  final String name;
  final String location;
  /// Short region label under the flag, e.g. `US-East`.
  final String regionCompact;
  final String network;
  final Color networkColor;
  final double loadValue;
  final String access;
  final bool supportsStealth;
  final int minTier;
  final VpnNodeOrg? org;
  final String? activityTime;
  final bool activityLive;
  final bool showSolanaBadge;
  final double? downloadMbps;
  final double? uploadMbps;
  final int? clientPingMs;
  final bool isPlaceholder;
  final bool showLoad;
  final bool showNodeSpeedtest;
  final bool showActivity;

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

  String get accessLabel => switch (access) {
        'private' => 'Private',
        _ => 'Public',
      };

  Color get accessColor => switch (access) {
        'private' => AppColors.accent,
        _ => AppColors.textMuted,
      };

  String? get tierLabel => minTier > 0 ? 'T$minTier' : null;

  String? get orgNameLine {
    final n = org?.name.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  String get downloadLabel => _mbpsLabel(downloadMbps);

  String get uploadLabel => _mbpsLabel(uploadMbps);

  static String _mbpsLabel(double? mbps) {
    if (mbps == null || mbps <= 0) return '—';
    if (mbps >= 100) return mbps.toStringAsFixed(0);
    if (mbps >= 10) return mbps.toStringAsFixed(1);
    return mbps.toStringAsFixed(2);
  }

  static NodeDisplay placeholder({bool registryError = false}) {
    return NodeDisplay(
      flag: '',
      name: registryError ? 'Registry unavailable' : 'Select a server',
      location: registryError
          ? 'Could not reach the node registry'
          : 'Community nodes on the Erebrus network',
      regionCompact: '',
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
    bool showActivity = false,
  }) {
    if (node == null || forcePlaceholder) return placeholder();
    final region = node.region.isEmpty ? 'Erebrus node' : node.region;
    final activity = _nodeActivity(node);
    return NodeDisplay(
      flag: _flag(node.region),
      name: node.name,
      location: _regionZoneLabel(region, node.zone),
      regionCompact: _regionCompact(region, node.zone),
      network: node.protocolsLabel,
      networkColor: node.supportsStealth ? AppColors.accent : AppColors.textTertiary,
      loadValue: node.loadPct,
      access: node.accessMode,
      supportsStealth: node.supportsStealth,
      minTier: node.minTier,
      org: node.org,
      activityTime: activity.time,
      activityLive: activity.live,
      showSolanaBadge: node.isSolana,
      downloadMbps: node.downloadMbps,
      uploadMbps: node.uploadMbps,
      clientPingMs: clientPingMs,
      showNodeSpeedtest: node.hasReportedSpeedtest,
      showActivity: showActivity,
    );
  }

  /// Uses whichever is newer: gateway heartbeat or latest peer WireGuard handshake.
  static ({String? time, bool live}) _nodeActivity(VpnNode node) {
    const handshakeWindow = Duration(minutes: 3);
    const heartbeatWindow = Duration(seconds: 90);

    final peerAt = _parseIso(node.lastPeerHandshake);
    final beatAt = _parseIso(node.lastHeartbeat);

    if (peerAt == null && beatAt == null) {
      return (time: null, live: !node.isOffline);
    }

    final peerIsLatest = peerAt != null && (beatAt == null || peerAt.isAfter(beatAt));
    final latestIso = peerIsLatest ? node.lastPeerHandshake : node.lastHeartbeat;
    final latestAt = peerIsLatest ? peerAt : beatAt!;
    final window = peerIsLatest ? handshakeWindow : heartbeatWindow;
    final live = !node.isOffline && DateTime.now().toUtc().difference(latestAt.toUtc()) <= window;
    return (time: _relativeAgo(latestIso), live: live);
  }

  static DateTime? _parseIso(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    return dt?.toUtc();
  }

  static String _relativeAgo(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '—';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.isNegative) return 'just now';
    final sec = diff.inSeconds;
    if (sec < 60) return '${sec}s ago';
    final min = diff.inMinutes;
    if (min < 60) return '${min}m ago';
    final hr = diff.inHours;
    if (hr < 24) return '${hr}h ago';
    return '${diff.inDays}d ago';
  }

  static String _regionCompact(String region, String? zone) {
    final z = zone?.trim();
    if (z == null || z.isEmpty) return region;
    return '$region-${_titleCase(z)}';
  }

  static String _regionZoneLabel(String region, String? zone) {
    final z = zone?.trim();
    if (z == null || z.isEmpty) return region;
    return '$region · ${_titleCase(z)}';
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

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