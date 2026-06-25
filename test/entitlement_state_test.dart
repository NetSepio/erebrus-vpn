import 'package:erebrus_vpn/auth/entitlement_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EntitlementState.fromJson parses no subscription', () {
    final ent = EntitlementState.fromJson({
      'status': 'none',
      'entitled': false,
      'nft_gating': true,
    });
    expect(ent.entitled, isFalse);
    expect(ent.status, 'none');
    expect(ent.nftGatingEnabled, isTrue);
    expect(ent.trialConsumed, isFalse);
    expect(ent.planLabel, 'Free');
  });

  test('EntitlementState.fromJson parses expired trial', () {
    final ent = EntitlementState.fromJson({
      'status': 'expired',
      'entitled': false,
      'source': 'trial',
      'trial_consumed': true,
    });
    expect(ent.trialConsumed, isTrue);
    expect(ent.entitled, isFalse);
    expect(ent.status, 'expired');
  });

  test('EntitlementState.fromJson parses active trial', () {
    final end = DateTime.utc(2026, 7, 5, 12);
    final ent = EntitlementState.fromJson({
      'status': 'active',
      'entitled': true,
      'plan_id': 'pro',
      'source': 'trial',
      'current_period_end': end.toIso8601String(),
    });
    expect(ent.entitled, isTrue);
    expect(ent.planId, 'pro');
    expect(ent.source, 'trial');
    expect(ent.planLabel, 'Pro');
    expect(ent.periodEnd, end);
  });

  test('EntitlementState.fromJson parses rank source', () {
    final ent = EntitlementState.fromJson({
      'status': 'active',
      'entitled': true,
      'source': 'rank',
      'plan_id': 'pro',
    });
    expect(ent.source, 'rank');
    expect(ent.entitled, isTrue);
  });

  test('daysRemaining counts down to zero', () {
    final ent = EntitlementState(
      entitled: true,
      planId: 'pro',
      source: 'trial',
      periodEnd: DateTime.now().toUtc().add(const Duration(days: 10, hours: 12)),
    );
    expect(ent.daysRemaining, 10);
  });
}