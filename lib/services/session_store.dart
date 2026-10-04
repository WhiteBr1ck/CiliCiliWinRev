import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// DPAPI binds ciphertext to the current Windows user and machine.
class WindowsSessionStore implements SessionStore {
  static const channel = MethodChannel('CiliCiliWinRev/session');
  final String fileName;
  const WindowsSessionStore({this.fileName = 'account.dpapi'});
  Future<File> file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$fileName');
  @override
  Future<String?> read() async {
    final target = await file();
    if (!await target.exists()) return null;
    final plain = await channel.invokeMethod<Uint8List>(
      'unprotect',
      await target.readAsBytes(),
    );
    return plain == null ? null : utf8.decode(plain);
  }

  @override
  Future<void> write(String token) async {
    final encrypted = await channel.invokeMethod<Uint8List>(
      'protect',
      Uint8List.fromList(utf8.encode(token)),
    );
    if (encrypted == null) {
      throw PlatformException(code: 'DPAPI', message: '无法加密登录信息');
    }
    final target = await file();
    await target.parent.create(recursive: true);
    await target.writeAsBytes(encrypted, flush: true);
  }

  @override
  Future<void> delete() async {
    final target = await file();
    if (await target.exists()) await target.delete();
  }
}
