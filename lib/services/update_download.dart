import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'update_public_key.dart';
import 'windows_updater.dart';

enum DownloadPhase { idle, downloading, verifying, installing, failed }

Future<Directory> updateDirectory() async {
  final temporary = await getTemporaryDirectory();
  final root = Directory('${temporary.path}/CiliCiliWinRev-updates');
  await root.create(recursive: true);
  return root.createTemp('update-');
}

/// CPU-heavy verification runs outside the UI isolate.
Future<bool> verifyUpdate(Map<String, String> values) async {
  final bytes = await File(values['path']!).readAsBytes();
  if (crypto.sha256.convert(bytes).toString() != values['sha256']) return false;
  return Ed25519().verify(
    bytes,
    signature: Signature(
      base64Decode(values['signature']!),
      publicKey: SimplePublicKey(
        base64Decode(values['publicKey']!),
        type: KeyPairType.ed25519,
      ),
    ),
  );
}

class UpdateDownload extends ChangeNotifier {
  final String repository, publicKey;
  final http.Client Function() clientFactory;
  final Future<Directory> Function() directoryFactory;
  final Future<void> Function() validateInstallation, cancelInstallation;
  final Future<void> Function(String, String, String) prepareInstallation;
  Future<void> Function()? shutdown;
  DownloadPhase phase = DownloadPhase.idle;
  int received = 0, total = 0;
  String error = '';
  http.Client? _client;
  Future<void>? _job;
  bool _cancelled = false, _disposed = false;

  UpdateDownload({
    required this.repository,
    this.publicKey = updatePublicKey,
    this.clientFactory = http.Client.new,
    this.directoryFactory = updateDirectory,
    this.validateInstallation = WindowsUpdater.validate,
    this.prepareInstallation = WindowsUpdater.prepare,
    this.cancelInstallation = WindowsUpdater.cancel,
  });

  bool get busy =>
      phase == DownloadPhase.downloading ||
      phase == DownloadPhase.verifying ||
      phase == DownloadPhase.installing;
  bool get cancellable =>
      phase == DownloadPhase.downloading || phase == DownloadPhase.verifying;
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;

  Future<void> start({
    required String version,
    required Uri installer,
    required int size,
  }) {
    if (_disposed) return Future.value();
    return _job ??= _start(
      version,
      installer,
      size,
    ).whenComplete(() => _job = null);
  }

  void _checkCancelled() {
    if (_cancelled || _disposed) throw const _Cancelled();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (!cancellable) return;
    _cancelled = true;
    _client?.close();
  }

  Future<void> _start(String version, Uri installer, int size) async {
    _cancelled = false;
    phase = DownloadPhase.downloading;
    error = '';
    received = 0;
    total = size;
    _notify();
    File? payload;
    Directory? folder;
    bool prepared = false, handedOff = false;
    try {
      if (shutdown == null) throw const FormatException('无法准备安装，请重新打开软件');
      await validateInstallation();
      _checkCancelled();
      final client = _client = clientFactory();
      final manifestResponse = await client
          .get(
            Uri.https(
              'raw.githubusercontent.com',
              '/$repository/main/updates/$version/windows.json',
            ),
          )
          .timeout(const Duration(seconds: 20));
      _checkCancelled();
      if (manifestResponse.statusCode != 200) {
        throw const FormatException('更新尚未准备就绪，请稍后重试');
      }
      dynamic manifest;
      try {
        manifest = jsonDecode(utf8.decode(manifestResponse.bodyBytes));
      } on FormatException {
        throw const FormatException('更新信息无效，请重新检查更新');
      }
      if (manifest is! Map ||
          manifest['version'] != version ||
          manifest['url'] != installer.toString() ||
          manifest['size'] != size ||
          size <= 0 ||
          size > 512 * 1024 * 1024 ||
          manifest['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest['sha256']) ||
          manifest['signature'] is! String ||
          !RegExp(r'^[A-Za-z0-9+/]{86}==$').hasMatch(manifest['signature'])) {
        throw const FormatException('更新信息无效，请重新检查更新');
      }
      folder = await directoryFactory();
      _checkCancelled();
      payload = File('${folder.path}/setup.exe');
      final response = await client
          .send(http.Request('GET', installer))
          .timeout(const Duration(seconds: 30));
      _checkCancelled();
      if (response.statusCode != 200) {
        throw FormatException('下载失败（HTTP ${response.statusCode}），请重试');
      }
      if (response.contentLength != null && response.contentLength != size) {
        throw const FormatException('安装包大小不符，请重试');
      }
      final sink = payload.openWrite();
      // Observe early disk errors immediately; flush/close still report them.
      unawaited(sink.done.catchError((Object _) {}));
      final watch = Stopwatch()..start();
      var lastNotification = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          _checkCancelled();
          received += chunk.length;
          if (received > size) throw const FormatException('安装包大小不符，请重试');
          sink.add(chunk);
          if (watch.elapsedMilliseconds - lastNotification >= 100) {
            lastNotification = watch.elapsedMilliseconds;
            _notify();
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      _checkCancelled();
      if (received != size) throw const FormatException('安装包下载不完整，请重试');
      phase = DownloadPhase.verifying;
      _notify();
      final verified = await compute(verifyUpdate, {
        'path': payload.path,
        'sha256': manifest['sha256'] as String,
        'signature': manifest['signature'] as String,
        'publicKey': publicKey,
      });
      _checkCancelled();
      if (!verified) throw const FormatException('安装包校验失败，请重新下载');
      phase = DownloadPhase.installing;
      _notify();
      await prepareInstallation(payload.path, manifest['sha256'], version);
      prepared = true;
      await shutdown!();
      handedOff = true;
    } on _Cancelled {
      phase = DownloadPhase.idle;
    } catch (e) {
      if (_cancelled || _disposed) {
        phase = DownloadPhase.idle;
      } else {
        phase = DownloadPhase.failed;
        error = e is FormatException
            ? e.message
            : e is TimeoutException
            ? '下载超时，请重试'
            : e is FileSystemException
            ? '无法保存安装包，请检查磁盘空间后重试'
            : e is PlatformException
            ? (e.message ?? '无法启动安装，请重试')
            : '更新失败，请检查网络后重试';
      }
    } finally {
      _client?.close();
      _client = null;
      if (prepared && !handedOff) {
        try {
          await cancelInstallation();
        } catch (_) {}
      }
      if (!handedOff && payload != null) {
        // Failed native handoffs may still hold the file briefly. The helper
        // retains it on install failure; it never runs without an explicit commit.
        try {
          if (await payload.exists()) await payload.delete();
        } catch (_) {}
      }
      if (!handedOff && folder != null) {
        try {
          if (await folder.exists() && await folder.list().isEmpty) {
            await folder.delete();
          }
        } catch (_) {}
      }
      _notify();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelled = true;
    _client?.close();
    super.dispose();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
