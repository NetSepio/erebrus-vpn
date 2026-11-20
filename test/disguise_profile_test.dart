import 'dart:io';

import 'package:erebrus_vpn/settings/disguise_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// The launcher disguise lives in two places that must agree: the
/// `<activity-alias>` entries in AndroidManifest.xml and [DisguiseProfile.all].
/// Nothing at runtime notices a mismatch — the icon simply fails to change, or
/// worse, the app vanishes from the launcher — so the agreement is asserted
/// here instead.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final strings = File(
    'android/app/src/main/res/values/strings.xml',
  ).readAsStringSync();

  /// Each `<activity-alias>` block, keyed by its android:name. An alias with no
  /// name lands under '', which the first test rejects.
  final blocks = <String, String>{};
  for (final m in RegExp(
    r'<activity-alias\b([\s\S]*?)</activity-alias>',
  ).allMatches(manifest)) {
    final block = m.group(1)!;
    final name =
        RegExp(r'android:name="([^"]+)"').firstMatch(block)?.group(1) ?? '';
    blocks[name] = block;
  }

  String? attr(String block, String name) =>
      RegExp('android:$name="([^"]+)"').firstMatch(block)?.group(1);

  test('every profile has an alias and every alias has a profile', () {
    expect(blocks.containsKey(''), isFalse,
        reason: 'an activity-alias has no android:name');
    expect(blocks.keys.toSet(), DisguiseProfile.aliases.toSet());
    expect(DisguiseProfile.all.map((p) => p.id).toSet().length,
        DisguiseProfile.all.length,
        reason: 'profile ids must be unique');
  });

  test('exactly one alias ships enabled, and it is the real one', () {
    final enabled = [
      for (final entry in blocks.entries)
        if (attr(entry.value, 'enabled') == 'true') entry.key,
    ];
    expect(enabled, [DisguiseProfile.erebrus.alias]);
  });

  test('aliases target MainActivity and carry the launcher filter', () {
    for (final entry in blocks.entries) {
      expect(attr(entry.value, 'targetActivity'), '.MainActivity',
          reason: '${entry.key} must open the real activity');
      expect(attr(entry.value, 'exported'), 'true',
          reason: '${entry.key} is a launcher entry, so it must be exported');
      expect(entry.value, contains('android.intent.action.MAIN'));
      expect(entry.value, contains('android.intent.category.LAUNCHER'));
    }
  });

  test('MainActivity keeps the deep link and gives up the launcher', () {
    final activity = RegExp(
      r'<activity\b[\s\S]*?android:name="\.MainActivity"[\s\S]*?</activity>',
    ).firstMatch(manifest)?.group(0);
    expect(activity, isNotNull);
    // Two launcher entries would appear in the launcher at once, which is the
    // opposite of a disguise.
    expect(activity, isNot(contains('android.intent.category.LAUNCHER')));
    // Deep links must survive every switch; they are how sign-in returns.
    expect(activity, contains('android:scheme="erebrusvpn"'));
  });

  test('labels and icons resolve to real resources with matching copy', () {
    for (final profile in DisguiseProfile.all) {
      final block = blocks[profile.alias]!;
      final label = attr(block, 'label')!;
      expect(label, startsWith('@string/'));
      final key = label.substring('@string/'.length);
      final value = RegExp('<string name="$key">([^<]+)</string>')
          .firstMatch(strings)
          ?.group(1);
      expect(value, profile.label,
          reason: '${profile.alias} shows "$value" in the launcher, '
              'the picker offers "${profile.label}"');

      for (final key in ['icon', 'roundIcon']) {
        final icon = attr(block, key)!;
        expect(icon, startsWith('@mipmap/'));
        final name = icon.substring('@mipmap/'.length);
        final candidates = [
          'android/app/src/main/res/mipmap-anydpi-v26/$name.xml',
          'android/app/src/main/res/mipmap-anydpi/$name.xml',
          'android/app/src/main/res/mipmap-hdpi/$name.png',
        ];
        expect(candidates.any((p) => File(p).existsSync()), isTrue,
            reason: '${profile.alias} $key points at $icon, which is missing');
      }
    }
  });

  test('a disguised notification never names the server', () {
    expect(DisguiseProfile.erebrus.isDisguised, isFalse);
    // The real profile keeps the copy the app has always shown.
    expect(DisguiseProfile.erebrus.notificationTitle, 'Erebrus');
    expect(
      DisguiseProfile.erebrus.notificationText('Frankfurt-1'),
      'Protected · Frankfurt-1',
    );
    for (final profile in DisguiseProfile.all.where((p) => p.isDisguised)) {
      expect(profile.notificationTitle, profile.label,
          reason: '${profile.id} must notify under its cover name');
      expect(profile.notificationText('Frankfurt-1'), isNot(contains('Frankfurt')),
          reason: '${profile.id} leaks the server into its notification');
      expect(profile.notificationText('Frankfurt-1').toLowerCase(),
          isNot(contains('erebrus')),
          reason: '${profile.id} leaks the brand into its notification');
    }
  });

  test('lookups fall back to the real profile', () {
    expect(DisguiseProfile.byAlias('.LauncherNotes'), DisguiseProfile.notes);
    expect(DisguiseProfile.byAlias('.LauncherNope'), DisguiseProfile.erebrus);
    expect(DisguiseProfile.byAlias(null), DisguiseProfile.erebrus);
    expect(DisguiseProfile.byId('calculator'), DisguiseProfile.calculator);
    expect(DisguiseProfile.byId('nope'), DisguiseProfile.erebrus);
  });
}
