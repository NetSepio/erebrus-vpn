import 'dart:convert';

import 'package:erebrus_vpn/vpn/wg_keygen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WgKeygen produces valid-looking base64 keypair', () {
    final keys = WgKeygen.generate();
    expect(keys.private, isNotEmpty);
    expect(keys.public, isNotEmpty);
    expect(base64Decode(keys.private).length, 32);
    expect(base64Decode(keys.public).length, 32);
    expect(keys.private, isNot(equals(keys.public)));
  });
}