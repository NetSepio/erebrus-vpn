import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/platform_capabilities.dart';
import 'clash_stats_poller.dart';
import 'singbox_engine.dart';

/// Runs the bundled sing-box CLI as a subprocess on macOS / Windows / Linux.
/// Same JSON configs as Android; no libbox FFI required on desktop.
class SingboxDesktopRunner {
  SingboxDesktopRunner._();
  static final instance = SingboxDesktopRunner._();

  Process? _process;
  String _stage = 'disconnected';
  final _stageCtrl = StreamController<VpnStage>.broadcast();
  final _statsPoller = ClashStatsPoller();
  StreamSubscription<VpnStats>? _statsSub;
  String? _lastError;

  Stream<VpnStage> get onStage => _stageCtrl.stream;
  Stream<VpnStats> get onStats => _statsPoller.stream;
  String get stage => _stage;
  String? get lastError => _lastError;

  /// Locates the sing-box binary shipped next to the app bundle / executable.
  Future<String?> findBinary() async {
    final exe = Platform.resolvedExecutable;
    final exeDir = p.dirname(exe);
    final name = Platform.isWindows ? 'sing-box.exe' : 'sing-box';

    final candidates = <String>[
      if (Platform.isMacOS) p.join(exeDir, '..', 'Resources', name),
      p.join(exeDir, name),
      p.join(exeDir, 'data', name),
      p.join(Directory.current.path, 'bin', name),
      p.join(Directory.current.path, 'native', name),
      if (Platform.environment['EREBRUS_SINGBOX'] != null)
        Platform.environment['EREBRUS_SINGBOX']!,
    ];

    for (final c in candidates) {
      final resolved = p.normalize(c);
      final f = File(resolved);
      if (await f.exists()) {
        debugPrint('[DesktopVPN] sing-box at $resolved');
        return resolved;
      }
    }
    debugPrint('[DesktopVPN] sing-box not found (searched ${candidates.length} paths)');
    return null;
  }

  Future<bool> prepare() async => (await findBinary()) != null;

  Future<void> start(String configJson, {String profileName = 'Erebrus'}) async {
    await stop();
    final binary = await findBinary();
    if (binary == null) {
      _setStage('error');
      _lastError =
          'sing-box binary missing — run ./scripts/fetch-singbox-cli.sh ${PlatformCapabilities.platformLabel}';
      throw StateError(_lastError!);
    }

    final dir = await Directory.systemTemp.createTemp('erebrus-singbox-');
    final configPath = p.join(dir.path, 'config.json');
    await File(configPath).writeAsString(configJson);
    debugPrint('[DesktopVPN] starting $binary ($profileName, ${configJson.length} bytes)');

    _setStage('connecting');
    _lastError = null;

    try {
      _process = await Process.start(
        binary,
        ['run', '-c', configPath, '--disable-color'],
        mode: ProcessStartMode.normal,
        workingDirectory: p.dirname(binary),
      );
    } catch (e) {
      _lastError = e.toString();
      _setStage('error');
      rethrow;
    }

    var sawStarted = false;
    void handleLine(String line) {
      debugPrint('[sing-box] $line');
      if (line.contains('sing-box started')) {
        sawStarted = true;
        _setStage('connected');
        _startStats();
      }
      if (line.contains('FATAL') || line.contains('ERROR')) {
        _lastError = line;
      }
    }

    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);

    _process!.exitCode.then((code) {
      _stopStats();
      if (_stage == 'disconnecting') {
        _setStage('disconnected');
      } else if (code != 0) {
        _lastError ??= 'sing-box exited ($code)';
        _setStage('error');
      } else if (!sawStarted) {
        _setStage('disconnected');
      }
      _process = null;
    });

    // Fallback: if log line missed, assume connected after short delay if still running.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_process != null && _stage == 'connecting') {
      _setStage('connected');
      _startStats();
    }
  }

  Future<void> stop() async {
    if (_process == null) {
      _setStage('disconnected');
      return;
    }
    _setStage('disconnecting');
    _stopStats();
    _process!.kill(ProcessSignal.sigterm);
    try {
      await _process!.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      _process!.kill(ProcessSignal.sigkill);
    }
    _process = null;
    _setStage('disconnected');
  }

  void _setStage(String value) {
    _stage = value;
    if (!_stageCtrl.isClosed) {
      _stageCtrl.add(switch (value) {
        'connecting' => VpnStage.connecting,
        'connected' => VpnStage.connected,
        'disconnecting' => VpnStage.disconnecting,
        'error' => VpnStage.error,
        _ => VpnStage.disconnected,
      });
    }
  }

  void _startStats() {
    _stopStats();
    unawaited(_statsPoller.start());
  }

  void _stopStats() {
    unawaited(_statsPoller.stop());
    _statsSub?.cancel();
    _statsSub = null;
  }

  void dispose() {
    _stopStats();
    _statsPoller.dispose();
    _stageCtrl.close();
  }
}