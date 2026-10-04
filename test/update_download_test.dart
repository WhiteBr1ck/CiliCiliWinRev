import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:clicli_md3/services/update_download.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = 'WhiteBr1ck/CiliCiliWinRev';
  final url = Uri.parse(
    'https://github.com/$repository/releases/download/v0.7.0/CiliCiliWinRev-0.7.0-windows-x64-setup.exe',
  );
  final bytes = List<int>.generate(1024, (i) => i % 251);
  late String publicKey;
  late Map<String, Object> manifest;
  late Directory root;
  late UpdateDownload download;
  late List<String> calls;
  late List<http.BaseRequest> requests;
  Map<String, Object> Function(Map<String, Object>)? alter;
  Stream<List<int>> Function()? stream;
  int status = 200;
  Future<void> Function()? prepare;
  Future<void> Function()? shutdown;

  setUpAll(() async {
    final key = await Ed25519().newKeyPair();
    publicKey = base64Encode((await key.extractPublicKey()).bytes);
    manifest = {
      'version': '0.7.0',
      'url': url.toString(),
      'size': bytes.length,
      'sha256': crypto.sha256.convert(bytes).toString(),
      'signature': base64Encode(
        (await Ed25519().sign(bytes, keyPair: key)).bytes,
      ),
    };
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('clicli-update-test-');
    calls = [];
    requests = [];
    alter = null;
    stream = null;
    status = 200;
    prepare = null;
    shutdown = null;
    download = UpdateDownload(
      repository: repository,
      publicKey: publicKey,
      directoryFactory: () => root.createTemp('payload-'),
      validateInstallation: () async {
        calls.add('validate');
      },
      prepareInstallation: (path, digest, version) async {
        expect(await File(path).readAsBytes(), bytes);
        expect(digest, manifest['sha256']);
        expect(version, '0.7.0');
        calls.add('prepare');
        await prepare?.call();
      },
      cancelInstallation: () async {
        calls.add('cancelHelper');
      },
      clientFactory: () => MockClient.streaming((request, _) async {
        requests.add(request);
        if (request.url.host == 'raw.githubusercontent.com') {
          expect(
            request.url.path,
            '/$repository/main/updates/0.7.0/windows.json',
          );
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(jsonEncode(alter?.call({...manifest}) ?? manifest)),
            ),
            200,
          );
        }
        return http.StreamedResponse(
          stream?.call() ?? Stream.value(bytes),
          status,
        );
      }),
    );
    download.shutdown = () async {
      calls.add('saveAndExit');
      await shutdown?.call();
    };
  });
  tearDown(() async {
    download.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });
  Future<void> start() =>
      download.start(version: '0.7.0', installer: url, size: bytes.length);

  test('Dart accepts a signature from the official publisher tool', () async {
    final fixture = jsonDecode(
      await File('test/fixtures/signed_update.json').readAsString(),
    );
    final payload = File('${root.path}/publisher-fixture.bin');
    final data = base64Decode(fixture['payload']);
    await payload.writeAsBytes(data);
    expect(
      await verifyUpdate({
        'path': payload.path,
        'sha256': crypto.sha256.convert(data).toString(),
        'signature': fixture['signature'],
        'publicKey': fixture['publicKey'],
      }),
      true,
    );
  });

  test(
    'one click downloads and verifies signed bytes before install, without account headers',
    () async {
      await start();
      expect(calls, ['validate', 'prepare', 'saveAndExit']);
      expect(download.phase, DownloadPhase.installing);
      expect(download.progress, 1);
      for (final request in requests) {
        expect(
          request.headers.keys.where(
            (k) => ['authorization', 'cookie'].contains(k.toLowerCase()),
          ),
          isEmpty,
        );
      }
      expect(
        await root
            .list(recursive: true)
            .where((f) => f.path.endsWith('setup.exe'))
            .length,
        1,
      );
    },
  );
  for (final field in ['version', 'url', 'size', 'sha256', 'signature']) {
    test('invalid manifest $field cannot download or install', () async {
      alter = (m) {
        m[field] = field == 'size' ? 1 : 'invalid';
        return m;
      };
      await start();
      expect(download.phase, DownloadPhase.failed);
      expect(calls, ['validate']);
      expect(requests.length, 1);
      expect(await root.list().isEmpty, true);
    });
  }
  test('valid format but wrong signature is rejected', () async {
    alter = (m) {
      m['signature'] = base64Encode(List.filled(64, 0));
      return m;
    };
    await start();
    expect(download.error, contains('校验失败'));
    expect(calls, ['validate']);
    expect(await root.list().isEmpty, true);
  });
  test(
    'modified bytes cannot pass signature even when untrusted hash matches',
    () async {
      final changed = [...bytes]..[0] = 77;
      stream = () => Stream.value(changed);
      alter = (m) {
        m['sha256'] = crypto.sha256.convert(changed).toString();
        return m;
      };
      await start();
      expect(download.error, contains('校验失败'));
      expect(calls, ['validate']);
      expect(await root.list().isEmpty, true);
    },
  );
  for (final kind in ['http', 'truncated', 'oversized', 'network']) {
    test(
      '$kind failure leaves application running and removes payload',
      () async {
        switch (kind) {
          case 'http':
            status = 503;
          case 'truncated':
            stream = () => Stream.value(bytes.sublist(0, 12));
          case 'oversized':
            stream = () => Stream.value([...bytes, 1]);
          case 'network':
            stream = () => Stream.error(const SocketException('fixture'));
        }
        await start();
        expect(download.phase, DownloadPhase.failed);
        expect(calls, ['validate']);
        expect(await root.list().isEmpty, true);
      },
    );
  }
  test(
    'cancel mid-transfer cleans partial download and permits retry',
    () async {
      final chunks = StreamController<List<int>>();
      stream = () => chunks.stream;
      final job = start();
      while (requests.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      chunks.add(bytes.sublist(0, 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      download.cancel();
      chunks.add(bytes.sublist(10));
      await chunks.close();
      await job;
      expect(download.phase, DownloadPhase.idle);
      expect(calls, ['validate']);
      expect(await root.list().isEmpty, true);
      stream = null;
      await start();
      expect(calls, ['validate', 'validate', 'prepare', 'saveAndExit']);
    },
  );
  test('duplicate click shares one transfer', () async {
    await Future.wait([start(), start()]);
    expect(requests.length, 2);
    expect(calls, ['validate', 'prepare', 'saveAndExit']);
  });
  test('native preparation error never exits', () async {
    prepare = () async {
      throw PlatformException(code: 'fixture', message: '准备失败');
    };
    await start();
    expect(download.phase, DownloadPhase.failed);
    expect(download.error, '准备失败');
    expect(calls, ['validate', 'prepare']);
  });
  test('save failure cancels prepared helper and retry succeeds', () async {
    shutdown = () async {
      throw const FormatException('保存失败');
    };
    await start();
    expect(download.error, '保存失败');
    expect(calls, ['validate', 'prepare', 'saveAndExit', 'cancelHelper']);
    shutdown = null;
    await start();
    expect(download.phase, DownloadPhase.installing);
  });
  test('disk directory failure never installs', () async {
    download.dispose();
    download = UpdateDownload(
      repository: repository,
      publicKey: publicKey,
      validateInstallation: () async {},
      directoryFactory: () async {
        throw const FileSystemException('fixture disk full');
      },
      clientFactory: () =>
          MockClient((_) async => http.Response(jsonEncode(manifest), 200)),
    );
    download.shutdown = () async {
      fail('must not exit');
    };
    await start();
    expect(download.error, contains('磁盘空间'));
  });
}
