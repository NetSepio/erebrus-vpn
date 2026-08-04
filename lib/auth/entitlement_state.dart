import '../plan_label.dart';

/// Entitlement from `GET /api/v2/subscriptions`.
class EntitlementState {
  const EntitlementState({
    required this.entitled,
    this.status = 'none',
    this.planId,
    this.capabilityTier = 'free',
    this.source,
    this.periodEnd,
    this.nftGatingEnabled = false,
    this.trialConsumed = false,
    this.orgMember = false,
  });

  final bool entitled;
  final String status;
  final String? planId;
  final String capabilityTier;

  /// `trial` | `nft` | `plan` | `admin` | `rank` | null. `plan` = entitled via an
  /// owned paid-plan org (ongoing; `periodEnd` is null).
  final String? source;
  final DateTime? periodEnd;
  final bool nftGatingEnabled;

  /// True when the wallet has already used its one-time v2 trial.
  final bool trialConsumed;

  /// Active member of at least one workspace (private org node access).
  final bool orgMember;

  static const none = EntitlementState(entitled: false);

  factory EntitlementState.fromJson(Map<String, dynamic> j) {
    final entitled = j['entitled'] == true;
    final endRaw = j['current_period_end'];
    DateTime? periodEnd;
    if (endRaw is String && endRaw.isNotEmpty) {
      periodEnd = DateTime.tryParse(endRaw);
    } else if (endRaw is int) {
      periodEnd = DateTime.fromMillisecondsSinceEpoch(
        endRaw * 1000,
        isUtc: true,
      );
    }
    return EntitlementState(
      entitled: entitled,
      status: (j['status'] ?? 'none').toString(),
      planId: j['plan_id']?.toString(),
      capabilityTier: (j['capability_tier'] ?? 'free').toString(),
      source: j['source']?.toString(),
      periodEnd: periodEnd,
      nftGatingEnabled: j['nft_gating'] == true,
      trialConsumed: j['trial_consumed'] == true,
      orgMember: j['org_member'] == true,
    );
  }

  int? get daysRemaining {
    final end = periodEnd;
    if (end == null) return null;
    final days = end.toUtc().difference(DateTime.now().toUtc()).inDays;
    return days < 0 ? 0 : days;
  }

  String get planLabel {
    if (!entitled) return 'Free';
    return erebrusPlanLabel(planId, fallback: 'Member');
  }
}
