/// Caller's XP standing from `GET /api/v2/rank/me`.
///
/// Lifetime [xpEarned] is the headline value shown on the referrals card. XP is
/// awarded after a referee qualifies (activates an organization membership), so
/// it is not present in the redeem or profile responses — this endpoint is the
/// only source of truth for XP.
class RankSummary {
  const RankSummary({
    this.xpEarned = 0,
    this.xpClaimable = 0,
    this.tier = 0,
    this.tierName = '',
    this.nextTierAt,
  });

  /// Lifetime XP earned across all drivers (referrals included).
  final int xpEarned;

  /// XP earned but not yet claimed (`xp_earned - xp_claimed`, floored at 0).
  final int xpClaimable;
  final int tier;
  final String tierName;

  /// Lifetime-XP threshold for the next tier, when there is one above the
  /// current standing.
  final int? nextTierAt;

  factory RankSummary.fromJson(Map<String, dynamic> j) => RankSummary(
        xpEarned: (j['xp_earned'] as num?)?.toInt() ?? 0,
        xpClaimable: (j['xp_claimable'] as num?)?.toInt() ?? 0,
        tier: (j['tier'] as num?)?.toInt() ?? 0,
        tierName: (j['tier_name'] ?? '').toString(),
        nextTierAt: (j['next_tier_at'] as num?)?.toInt(),
      );
}
