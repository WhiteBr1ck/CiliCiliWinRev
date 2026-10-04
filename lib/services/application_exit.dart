import 'package:flutter/services.dart';

class ApplicationExit {
  static const _channel = MethodChannel('CiliCiliWinRev/window');
  /// Call only after application data has been persisted.
  static Future<void> finish() => _channel.invokeMethod('exitApplication');
}
