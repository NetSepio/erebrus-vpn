import 'dart:io';

import 'package:flutter/foundation.dart';

/// Routes Linux desktop HTTP/HTTPS/SOCKS through gsettings (GNOME / most GTK desktops).
class LinuxSystemProxy {
  LinuxSystemProxy._();

  static Future<bool> get _hasGsettings async {
    final r = await Process.run('which', ['gsettings']);
    return r.exitCode == 0;
  }

  static Future<void> enable({
    String host = '127.0.0.1',
    int port = 10808,
  }) async {
    if (!Platform.isLinux) return;
    if (!await _hasGsettings) {
      debugPrint('[Linux] gsettings not found — system proxy not set');
      return;
    }
    try {
      final cmds = <List<String>>[
        ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'manual'],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'host', host],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'port', '$port'],
        ['gsettings', 'set', 'org.gnome.system.proxy.https', 'host', host],
        ['gsettings', 'set', 'org.gnome.system.proxy.https', 'port', '$port'],
        ['gsettings', 'set', 'org.gnome.system.proxy.socks', 'host', host],
        ['gsettings', 'set', 'org.gnome.system.proxy.socks', 'port', '$port'],
      ];
      for (final cmd in cmds) {
        final r = await Process.run(cmd.first, cmd.sublist(1));
        if (r.exitCode != 0) {
          debugPrint('[Linux] ${cmd.join(' ')} failed: ${r.stderr}');
          return;
        }
      }
      debugPrint('[Linux] system proxy enabled → $host:$port');
    } catch (e) {
      debugPrint('[Linux] system proxy enable failed: $e');
    }
  }

  static Future<void> disable() async {
    if (!Platform.isLinux) return;
    if (!await _hasGsettings) return;
    try {
      final r = await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'none']);
      if (r.exitCode == 0) {
        debugPrint('[Linux] system proxy disabled');
      }
    } catch (e) {
      debugPrint('[Linux] system proxy disable failed: $e');
    }
  }
}