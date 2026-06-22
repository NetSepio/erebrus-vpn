import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/macos_privileged_process.dart';
import '../platform/macos_system_proxy.dart';
import '../platform/platform_capabilities.dart';
import 'clash_stats_poller.dart';
import 'singbox_engine.dart';
import 'vpn_models.dart';

/// Runs the bundled sing-box CLI as a subprocess on macOS / Windows / Linux.
///
/// On macOS, unsigned desktop builds use **proxy-only** (mixed inbound on
/// 127.0.0.1:10808 + system HTTP/SOCKS via `networksetup`). Configs that still
/// include a TUN inbound can be started via an administrator prompt when needed.
class SingboxDesktopRunner {
  SingboxDesktopRunner._();
  static final instance = SingboxDesktopRunner._();

  Process? _process;
  bool _privilegedMacos = false;
  String? _workDir;
  String? _pidPath;
  String? _logPath;
  StreamSubscription<void>? _logTailer;

  String _stage = 'disconnected';
  final _stageCtrl = StreamController<VpnStage>.broadcast();
  final _statsPoller = ClashStatsPoller();
  StreamSubscription<VpnStats>? _statsSub;
  String? _lastError;

  Stream<VpnStage> get onStage => _stageCtrl.stream;
  Stream<VpnStats> get onStats => _statsPoller.stream;
  String get stage => _stage;
  String? get lastError => _lastError;

  Future<String?> findBinary() async {
    final exe = Platform.resolvedExecutable;
    final exeDir = p.dirname(exe);
    final name = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    final cwd = Directory.current.path;

    final candidates = <String>[
      if (Platform.environment['EREBRUS_SINGBOX'] != null)
        Platform.environment['EREBRUS_SINGBOX']!,
      if (Platform.isMacOS) p.join(exeDir, '..', 'Resources', name),
      p.join(exeDir, name),
      p.join(exeDir, 'data', name),
      p.join(cwd, 'bin', 'sing-box', 'darwin-arm64', name),
      p.join(cwd, 'bin', 'sing-box', 'darwin-amd64', name),
      p.join(cwd, 'bin', 'sing-box', 'linux-amd64', name),
      p.join(cwd, 'bin', 'sing-box', 'windows-amd64', '$name.exe'),
      p.join(cwd, 'bin', name),
      p.join(cwd, 'native', name),
    ];

    for (final c in candidates) {
      final resolved = p.normalize(c);
      if (await File(resolved).exists()) {
        debugPrint('[DesktopVPN] sing-box at $resolved');
        return resolved;
      }
    }
    debugPrint('[DesktopVPN] sing-box not found (searched ${candidates.length} paths)');
    return null;
  }

  Future<bool> prepare() async {
    final binary = await findBinary();
    if (binary != null) return true;
    _lastError =
        'sing-box binary missing — run ./scripts/setup-macos-dev.sh (or fetch-singbox-cli.sh macos)';
    return false;
  }

  Future<void> start(String configJson, {String profileName = 'Erebrus'}) async {
    await stop();
    final binary = await findBinary();
    if (binary == null) {
      _setStage('error');
      _lastError =
          'sing-box binary missing — run ./scripts/fetch-singbox-cli.sh ${PlatformCapabilities.platformLabel}';
      throw StateError(_lastError!);
    }

    _workDir = (await Directory.systemTemp.createTemp('erebrus-singbox-')).path;
    final configPath = p.join(_workDir!, 'config.json');
    await File(configPath).writeAsString(configJson);
    _logPath = p.join(_workDir!, 'singbox.log');
    _pidPath = p.join(_workDir!, 'singbox.pid');

    debugPrint('[DesktopVPN] starting $binary ($profileName, ${configJson.length} bytes)');
    _setStage('connecting');
    _lastError = null;
    if (Platform.isMacOS) {
      await MacosSystemProxy.disable();
    }

    final wantsTun = _configUsesTun(configJson);
    if (Platform.isMacOS && wantsTun) {
      final elevated = await _startPrivilegedMacos(binary, configPath);
      if (elevated) {
        await _awaitReady(privileged: true);
        return;
      }
      debugPrint('[DesktopVPN] admin declined or TUN start failed — falling back to proxy mode');
      final proxyConfig = _stripTunInbound(configJson);
      await File(configPath).writeAsString(proxyConfig);
      await _startSubprocess(binary, configPath);
      await _awaitReady(privileged: false, enableSystemProxy: true);
      return;
    }

    if (Platform.isMacOS && !wantsTun) {
      await _startSubprocess(binary, configPath);
      await _awaitReady(privileged: false, enableSystemProxy: true);
      return;
    }

    await _startSubprocess(binary, configPath);
    await _awaitReady(privileged: false, enableSystemProxy: false);
  }

  Future<bool> _startPrivilegedMacos(String binary, String configPath) async {
    final q = MacosPrivilegedProcess.shellQuote;
    final cmd =
        'nohup ${q(binary)} run -c ${q(configPath)} --disable-color >> ${q(_logPath!)} 2>&1 & echo \$! > ${q(_pidPath!)}';
    debugPrint('[DesktopVPN] requesting administrator access for TUN…');
    final ok = await MacosPrivilegedProcess.runShellScript(cmd);
    if (!ok) {
      _lastError = 'Administrator permission required for system VPN (TUN)';
      return false;
    }
    _privilegedMacos = true;
    _process = null;
    _startLogTail();
    return true;
  }

  Future<void> _startSubprocess(String binary, String configPath) async {
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

    _process!.exitCode.then((code) async {
      _stopStats();
      await MacosSystemProxy.disable();
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
  }

  Future<void> _awaitReady({
    required bool privileged,
    bool enableSystemProxy = false,
  }) async {
    final ready = await _waitUntilReady(
      hasFatal: () => _lastError != null && _lastError!.contains('FATAL'),
      processAlive: () => privileged ? _privilegedMacos : _process != null,
    );
    if (!ready) {
      _lastError ??= privileged
          ? 'sing-box did not start after admin elevation'
          : 'sing-box did not start — check logs for TUN/permission errors';
      _setStage('error');
      await stop();
      throw StateError(_lastError!);
    }
    if (_stage != 'connected') {
      _setStage('connected');
      _startStats();
    }
    if (Platform.isMacOS) {
      // Route Safari/Chrome through the local mixed inbound (same path as egress probe).
      // TUN alone often breaks DNS for system browsers on unsigned macOS CLI builds.
      await MacosSystemProxy.enable(
        host: SingboxConfigBuilder.localProxyHost,
        port: SingboxConfigBuilder.localProxyPort,
      );
      if (privileged) {
        debugPrint('[DesktopVPN] TUN + system HTTP/SOCKS proxy → 127.0.0.1:10808');
      } else if (enableSystemProxy) {
        debugPrint('[DesktopVPN] system HTTP/SOCKS proxy → 127.0.0.1:10808');
      }
    }
  }

  Future<bool> _waitUntilReady({
    required bool Function() hasFatal,
    required bool Function() processAlive,
  }) async {
    for (var i = 0; i < 60; i++) {
      if (hasFatal() || !processAlive()) return false;
      if (_stage == 'connected' || await _clashApiReachable()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return processAlive() && await _clashApiReachable();
  }

  Future<bool> _clashApiReachable() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 1);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:9090/'));
      final res = await req.close();
      await res.drain();
      client.close(force: true);
      if (res.statusCode == 200 || res.statusCode == 404) {
        if (_stage == 'connecting') {
          _setStage('connected');
          _startStats();
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _startLogTail() {
    _logTailer?.cancel();
    final logFile = _logPath;
    if (logFile == null) return;
    var offset = 0;
    _logTailer = Stream.periodic(const Duration(milliseconds: 400)).listen((_) async {
      try {
        final f = File(logFile);
        if (!await f.exists()) return;
        final len = await f.length();
        if (len <= offset) return;
        final chunk = await f.openRead(offset, len).transform(utf8.decoder).join();
        offset = len;
        for (final line in chunk.split('\n')) {
          if (line.isEmpty) continue;
          debugPrint('[sing-box] $line');
          if (line.contains('sing-box started')) {
            _setStage('connected');
            _startStats();
          }
          if (line.contains('FATAL') || line.contains('ERROR')) {
            _lastError = line;
          }
        }
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    await MacosSystemProxy.disable();
    _logTailer?.cancel();
    _logTailer = null;

    if (_privilegedMacos) {
      _setStage('disconnecting');
      _stopStats();
      final q = MacosPrivilegedProcess.shellQuote;
      final pidFile = _pidPath;
      if (pidFile != null) {
        await MacosPrivilegedProcess.runShellScript(
          'if [ -f ${q(pidFile)} ]; then kill \$(cat ${q(pidFile)}) 2>/dev/null; rm -f ${q(pidFile)}; fi',
        );
      }
      await MacosPrivilegedProcess.runShellScript('killall sing-box 2>/dev/null || true');
      _privilegedMacos = false;
      _setStage('disconnected');
      return;
    }

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

  bool _configUsesTun(String configJson) {
    try {
      final m = jsonDecode(configJson) as Map<String, dynamic>;
      final inbounds = (m['inbounds'] as List?) ?? const [];
      return inbounds.any((e) => (e as Map)['type'] == 'tun');
    } catch (_) {
      return true;
    }
  }

  String _stripTunInbound(String configJson) {
    final m = jsonDecode(configJson) as Map<String, dynamic>;
    final inbounds = ((m['inbounds'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((e) => e['type'] != 'tun')
        .toList();
    m['inbounds'] = inbounds;
    return const JsonEncoder.withIndent('  ').convert(m);
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
    _logTailer?.cancel();
    _statsPoller.dispose();
    _stageCtrl.close();
  }
}