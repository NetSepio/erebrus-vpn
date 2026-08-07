import 'package:erebrus_vpn/plan_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats known personal and business plan ids', () {
    expect(erebrusPlanLabel('personal.pro'), 'Personal · Pro');
    expect(erebrusPlanLabel('BUSINESS.SCALE'), 'Business · Scale');
  });

  test('formats future dotted plan ids without exposing raw ids', () {
    expect(erebrusPlanLabel('partner.premium'), 'Partner · Premium');
  });

  test('uses the requested fallback when a plan is absent', () {
    expect(erebrusPlanLabel(null, fallback: 'Member'), 'Member');
    expect(erebrusPlanLabel('  ', fallback: 'Unknown'), 'Unknown');
  });
}
