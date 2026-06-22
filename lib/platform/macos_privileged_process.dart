import 'dart:io';

import 'package:flutter/foundation.dart';

/// Runs a shell command with the standard macOS administrator password prompt.
class MacosPrivilegedProcess {
  MacosPrivilegedProcess._();

  /// Shell-escapes [value] for use inside `sh -c` (single-quoted).
  static String shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  /// Returns true when [osascript] completed; false if the user cancelled or the script failed.
  static Future<bool> runShellScript(String shellCommand) async {
    if (!Platform.isMacOS) return false;
    final script =
        'do shell script ${shellQuote(shellCommand)} with administrator privileges';
    try {
      final result = await Process.run('osascript', ['-e', script]);
      if (result.exitCode != 0) {
        final err = '${result.stderr}'.trim();
        debugPrint('[macOS] admin prompt failed ($err)');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[macOS] admin prompt error: $e');
      return false;
    }
  }
}