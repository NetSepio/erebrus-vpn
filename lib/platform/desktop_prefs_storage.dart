import 'package:shared_preferences/shared_preferences.dart';

/// Plain local persistence for unsigned macOS/desktop dev (no Keychain prompts).
class DesktopPrefsStorage {
  DesktopPrefsStorage._();

  static const _prefix = 'erebrus_store_';

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  static Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}