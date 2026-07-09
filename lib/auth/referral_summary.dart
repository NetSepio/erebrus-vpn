/// Gateway referral summary (`GET /api/v2/referrals/me`). Wallets arrive
/// pre-truncated by the gateway (first6…last4).
class ReferralSummary {
  const ReferralSummary({
    required this.code,
    this.referredCount = 0,
    this.referredBy = '',
    this.recent = const [],
  });

  /// The caller's shareable invite code (allocated lazily server-side).
  final String code;
  final int referredCount;

  /// Truncated wallet of whoever invited this account; empty when unbound.
  final String referredBy;
  final List<ReferralRecent> recent;

  /// Referees who started their trial — the action that pays XP.
  int get qualifiedCount => recent.where((r) => r.qualified).length;

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        code: (j['code'] ?? '').toString(),
        referredCount: (j['referred_count'] as num?)?.toInt() ?? 0,
        referredBy: (j['referred_by'] ?? '').toString(),
        recent: [
          for (final r in (j['recent'] as List? ?? const []))
            if (r is Map) ReferralRecent.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
}

/// One recent referee in a referral summary.
class ReferralRecent {
  const ReferralRecent({
    required this.wallet,
    required this.qualified,
    this.joinedAt,
  });

  final String wallet;
  final bool qualified;
  final DateTime? joinedAt;

  factory ReferralRecent.fromJson(Map<String, dynamic> j) => ReferralRecent(
        wallet: (j['wallet'] ?? '').toString(),
        qualified: j['qualified'] == true,
        joinedAt: DateTime.tryParse((j['joined_at'] ?? '').toString())?.toUtc(),
      );
}
