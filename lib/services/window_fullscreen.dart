import 'package:flutter/services.dart';

abstract final class WindowFullscreen {
  static const channel = MethodChannel('CiliCiliWinRev/window');
  static Future<void> set(bool value) =>
      channel.invokeMethod<void>('setFullscreen', value);
  static Future<Map<String, dynamic>> geometry() async =>
      Map<String, dynamic>.from(
        await channel.invokeMethod<Map>('geometry') ?? {},
      );
}
