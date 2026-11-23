import 'package:flutter/services.dart';

import '../platform/app_channels.dart';
import '../platform/platform_capabilities.dart';

/// A launcher disguise: the name and icon the app wears in the launcher, and
/// the copy its ongoing VPN notification uses.
///
/// Each profile maps to an `<activity-alias>` in
/// `android/app/src/main/AndroidManifest.xml`, and exactly one alias is enabled
/// at a time. [alias] is the contract between the two sides —
/// `test/disguise_profile_test.dart` fails if the manifest and this list drift
/// apart — so an alias is never renamed on one side alone.
///
/// A disguise hides that Erebrus is *installed*. It does not protect what is
/// stored: an unlocked device still hands over everything the app holds. Say
/// "discreet", never "seizure-proof".
class DisguiseProfile {
  const DisguiseProfile({
    required this.id,
    required this.alias,
    required this.label,
    required this.description,
    required this.notificationTitle,
    this.notificationDetail,
  });

  /// Stable key, persisted nowhere: the enabled alias is the source of truth.
  final String id;

  /// Manifest `<activity-alias android:name>`, relative to the app package.
  final String alias;

  /// What the launcher shows.
  final String label;

  /// One line of explanation in the picker.
  final String description;

  /// Title of the ongoing tunnel notification.
  final String notificationTitle;

  /// Body of that notification. Null means the real one, which names the
  /// server; a disguise must not, or the notification undoes the icon.
  final String? notificationDetail;

  bool get isDisguised => alias != erebrus.alias;

  /// Notification body for a tunnel to [serverName].
  String notificationText(String serverName) =>
      notificationDetail ?? 'Protected · $serverName';

  static const erebrus = DisguiseProfile(
    id: 'default',
    alias: '.LauncherDefault',
    label: 'Erebrus VPN',
    description: 'The real name and icon',
    notificationTitle: 'Erebrus',
  );

  static const notes = DisguiseProfile(
    id: 'notes',
    alias: '.LauncherNotes',
    label: 'Notes',
    description: 'Looks like a notepad',
    notificationTitle: 'Notes',
    notificationDetail: 'Syncing notes',
  );

  static const calculator = DisguiseProfile(
    id: 'calculator',
    alias: '.LauncherCalc',
    label: 'Calculator',
    description: 'Looks like a calculator',
    notificationTitle: 'Calculator',
    notificationDetail: 'Running',
  );

  static const weather = DisguiseProfile(
    id: 'weather',
    alias: '.LauncherWeather',
    label: 'Weather',
    description: 'Looks like a weather app',
    notificationTitle: 'Weather',
    notificationDetail: 'Updating forecast',
  );

  static const all = <DisguiseProfile>[erebrus, notes, calculator, weather];

  static List<String> get aliases => [for (final p in all) p.alias];

  static DisguiseProfile byAlias(String? alias) =>
      all.firstWhere((p) => p.alias == alias, orElse: () => erebrus);

  static DisguiseProfile byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => erebrus);

  /// The profile the launcher is currently wearing, as last read from the
  /// platform. Cached because the connect path needs the notification copy
  /// without awaiting a channel call; [DisguiseChannel.current] refreshes it.
  static DisguiseProfile active = erebrus;
}

/// Platform side of the launcher disguise. Android only — iOS has no way to
/// change an installed app's icon set from code, and [PlatformCapabilities
/// .supportsLauncherDisguise] is false there, so the UI never offers it.
class DisguiseChannel {
  const DisguiseChannel({this.channel = kAppMethodsChannel});

  /// Injected in tests; the app always uses the shared app methods channel.
  final MethodChannel channel;

  /// Reads the enabled alias and refreshes [DisguiseProfile.active].
  Future<DisguiseProfile> current() async {
    if (!PlatformCapabilities.supportsLauncherDisguise) {
      return DisguiseProfile.active = DisguiseProfile.erebrus;
    }
    try {
      final alias = await channel.invokeMethod<String>('disguise.current', {
        'aliases': DisguiseProfile.aliases,
      });
      return DisguiseProfile.active = DisguiseProfile.byAlias(alias);
    } on PlatformException {
      return DisguiseProfile.active;
    } on MissingPluginException {
      return DisguiseProfile.active;
    }
  }

  /// Switches the launcher to [profile]. Returns false when the platform
  /// refused, which means the manifest and [DisguiseProfile.all] disagree.
  Future<bool> set(DisguiseProfile profile) async {
    if (!PlatformCapabilities.supportsLauncherDisguise) return false;
    try {
      final ok = await channel.invokeMethod<bool>('disguise.set', {
        'alias': profile.alias,
        'aliases': DisguiseProfile.aliases,
      });
      if (ok == true) DisguiseProfile.active = profile;
      return ok == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
