import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:erebrus_vpn/auth/rank_summary.dart';

void main() {
  test('RankSummary parses the rank/me response', () {
    final j = jsonDecode('''
    {
      "xp_earned": 1250,
      "xp_claimed": 500,
      "xp_claimable": 750,
      "tier": 2,
      "tier_name": "Contributor",
      "next_tier_at": 2000,
      "breakdown_by_kind": {"referral": 1000, "connect": 250}
    }
    ''') as Map<String, dynamic>;
    final r = RankSummary.fromJson(j);
    expect(r.xpEarned, 1250);
    expect(r.xpClaimable, 750);
    expect(r.tier, 2);
    expect(r.tierName, 'Contributor');
    expect(r.nextTierAt, 2000);
  });

  test('RankSummary tolerates missing fields (top tier, no XP)', () {
    final r = RankSummary.fromJson(const {'xp_earned': 0});
    expect(r.xpEarned, 0);
    expect(r.xpClaimable, 0);
    expect(r.tier, 0);
    expect(r.tierName, '');
    expect(r.nextTierAt, isNull);
  });
}
