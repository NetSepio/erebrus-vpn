/// A pending organization invite for the authenticated user
/// (`GET /api/v2/account/org-invites`).
class UserOrgInvite {
  const UserOrgInvite({
    required this.id,
    required this.orgId,
    required this.orgName,
    this.orgSlug,
    this.role,
    this.seatTier,
    this.source,
    this.invitedByName,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String orgName;
  final String? orgSlug;
  final String? role;
  final String? seatTier;
  final String? source;
  final String? invitedByName;
  final DateTime? createdAt;

  factory UserOrgInvite.fromJson(Map<String, dynamic> j) => UserOrgInvite(
        id: (j['id'] ?? '').toString(),
        orgId: (j['org_id'] ?? '').toString(),
        orgName: (j['org_name'] ?? '').toString(),
        orgSlug: j['org_slug']?.toString(),
        role: j['role']?.toString(),
        seatTier: j['seat_tier']?.toString(),
        source: j['source']?.toString(),
        invitedByName: j['invited_by_name']?.toString(),
        createdAt: _parseDateTime(j['created_at']),
      );

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toUtc();
    } catch (_) {
      return null;
    }
  }
}
