import 'package:flutter/services.dart';

/// A separate native process waits for persisted data and client exit before
/// running the installer. All download UI stays inside the Flutter client.
class WindowsUpdater {
  static const channel = MethodChannel('CiliCiliWinRev/updater');
  static Future<void> validate() => channel.invokeMethod('validate');
  static Future<void> prepare(
    String installer,
    String digest,
    String version,
  ) => channel.invokeMethod('prepare', {
    'installer': installer,
    'sha256': digest,
    'version': version,
  });
  static Future<void> commit() => channel.invokeMethod('commit');
  static Future<void> cancel() => channel.invokeMethod('cancel');
}
