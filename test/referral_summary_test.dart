import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:erebrus_vpn/auth/referral_summary.dart';

void main() {
  test('ReferralSummary parses the gateway response', () {
    final j = jsonDecode('''
    {
      "code": "AB12CD34",
      "referred_count": 3,
      "referred_by": "0x1234…abcd",
      "recent": [
        {"wallet": "9xQe…3fKm", "qualified": true, "joined_at": "2026-07-01T10:00:00Z"},
        {"wallet": "0x9f8e…11aa", "qualified": false, "joined_at": "2026-07-05T09:30:00Z"}
      ]
    }
    ''') as Map<String, dynamic>;
    final s = ReferralSummary.fromJson(j);
    expect(s.code, 'AB12CD34');
    expect(s.referredCount, 3);
    expect(s.referredBy, '0x1234…abcd');
    expect(s.recent.length, 2);
    expect(s.qualifiedCount, 1);
    expect(s.recent.first.joinedAt, DateTime.utc(2026, 7, 1, 10));
  });

  test('ReferralSummary tolerates missing fields', () {
    final s = ReferralSummary.fromJson(const {'code': 'ZZZZ9999'});
    expect(s.code, 'ZZZZ9999');
    expect(s.referredCount, 0);
    expect(s.referredBy, '');
    expect(s.recent, isEmpty);
    expect(s.qualifiedCount, 0);
  });
}
