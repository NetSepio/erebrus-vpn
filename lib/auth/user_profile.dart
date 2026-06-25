/// Gateway account profile (`GET /api/v2/account/profile`).
class UserProfile {
  const UserProfile({
    required this.id,
    this.walletAddress,
    this.chain,
    this.role = 'user',
    this.email,
    this.emailVerified = false,
    this.name,
  });

  final String id;
  final String? walletAddress;
  final String? chain;
  final String role;
  final String? email;
  final bool emailVerified;
  final String? name;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: (j['id'] ?? '').toString(),
        walletAddress: j['wallet_address']?.toString(),
        chain: j['chain']?.toString(),
        role: (j['role'] ?? 'user').toString(),
        email: j['email']?.toString(),
        emailVerified: j['email_verified'] == true,
        name: j['name']?.toString(),
      );
}