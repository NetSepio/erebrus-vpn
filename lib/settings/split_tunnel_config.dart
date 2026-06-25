/// How per-app split tunneling applies on Android.
enum SplitTunnelMode {
  /// Only selected apps are routed through the VPN.
  include,

  /// Selected apps bypass the VPN; everything else is protected.
  exclude;

  static SplitTunnelMode fromName(String? raw) =>
      raw == 'include' ? SplitTunnelMode.include : SplitTunnelMode.exclude;

  String settingsSubtitle(int count) => switch (this) {
        SplitTunnelMode.include =>
          count == 0 ? 'VPN only — tap to pick apps' : 'VPN for $count app${count == 1 ? '' : 's'}',
        SplitTunnelMode.exclude =>
          count == 0 ? 'Bypass mode — tap to pick apps' : '$count app${count == 1 ? '' : 's'} bypass VPN',
      };

  String get segmentLabel => switch (this) {
        SplitTunnelMode.include => 'VPN only',
        SplitTunnelMode.exclude => 'Bypass',
      };

  String get hint => switch (this) {
        SplitTunnelMode.include => 'Only checked apps use the VPN.',
        SplitTunnelMode.exclude => 'Checked apps skip the VPN. Everything else is protected.',
      };
}

/// Active split-tunnel state passed to the Android VpnService on connect.
class SplitTunnelConfig {
  const SplitTunnelConfig({
    this.enabled = false,
    this.mode = SplitTunnelMode.exclude,
    this.packages = const [],
  });

  final bool enabled;
  final SplitTunnelMode mode;
  final List<String> packages;
}