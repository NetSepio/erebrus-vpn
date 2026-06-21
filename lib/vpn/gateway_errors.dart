import 'gateway_client.dart';

/// Turns raw gateway errors into short, actionable copy for the connect UI.
String friendlyGatewayError(Object error, {String? nodeName}) {
  final raw = switch (error) {
    GatewayException(:final message) => message,
    _ => error.toString(),
  };
  final lower = raw.toLowerCase();
  final node = nodeName ?? 'the node';

  if (lower.contains('no active subscription')) {
    return 'No active subscription — start a free trial in Account first';
  }
  if (lower.contains('node unreachable') || lower.contains('no reachable api')) {
    return 'Gateway cannot reach $node (port 9080). '
        'The node may need to re-register with the gateway, or the server '
        'firewall must allow the gateway to call the node API.';
  }
  if (lower.contains('client limit')) {
    return 'Client limit reached for your plan — remove an old device in Account';
  }
  if (lower.contains('node not found')) {
    return 'Node no longer registered — refresh Servers and pick another node';
  }
  if (lower.contains('node is draining')) {
    return '$node is draining — choose another server';
  }
  return raw;
}