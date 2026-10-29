import 'package:flutter/services.dart';

/// App-level method channel served by the native runners (deep links,
/// Android `moveTaskToBack`). Shared so callers cannot drift apart.
const kAppMethodsChannel = MethodChannel('com.erebrus.vpn/methods');
