import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'auth_config.dart';

/// Loads secrets from the project-root `.env` bundled as an app asset.
/// Compile-time `--dart-define-from-file` still wins when set.
class RuntimeConfig {
  RuntimeConfig._();

  static final _values = <String, String>{};

  static String get reownProjectId =>
      _firstNonEmpty([kReownProjectId, _values['REOWN_PROJECT_ID']]);

  static bool get hasReownProjectId => reownProjectId.isNotEmpty;

  static Future<void> load() async {
    if (kReownProjectId.isNotEmpty) {
      debugPrint('[Config] REOWN_PROJECT_ID from --dart-define');
      return;
    }
    await _loadDotEnvAsset('.env');
    final reown = _values['REOWN_PROJECT_ID'];
    if (reown != null && reown.isNotEmpty) {
      debugPrint('[Config] REOWN_PROJECT_ID loaded from bundled env');
    } else {
      debugPrint('[Config] REOWN_PROJECT_ID missing — add to .env and rebuild');
    }
  }

  static Future<void> _loadDotEnvAsset(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      _values.addAll(_parseDotEnv(raw));
    } catch (e) {
      debugPrint('[Config] could not load asset $path: $e');
    }
  }

  static Map<String, String> _parseDotEnv(String content) {
    final out = <String, String>{};
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final i = t.indexOf('=');
      if (i <= 0) continue;
      final key = t.substring(0, i).trim();
      var value = t.substring(i + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  static String _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final v = c?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }
}