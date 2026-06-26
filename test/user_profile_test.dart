import 'package:erebrus_vpn/auth/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserProfile parses gateway profile fields', () {
    final profile = UserProfile.fromJson({
      'id': 'u1',
      'wallet_address': 'abc123',
      'chain': 'SOLANA',
      'role': 'admin',
      'email': 'a@b.com',
      'email_verified': true,
      'name': 'Alice',
      'created_at': '2025-06-15T10:30:00Z',
    });

    expect(profile.id, 'u1');
    expect(profile.walletAddress, 'abc123');
    expect(profile.chain, 'SOLANA');
    expect(profile.role, 'admin');
    expect(profile.email, 'a@b.com');
    expect(profile.emailVerified, isTrue);
    expect(profile.name, 'Alice');
    expect(profile.createdAt, DateTime.utc(2025, 6, 15, 10, 30));
  });
}