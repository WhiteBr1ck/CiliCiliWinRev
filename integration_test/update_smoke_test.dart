import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:clicli_md3/services/app_updates.dart';
import 'package:clicli_md3/services/update_download.dart';
import 'package:clicli_md3/services/windows_updater.dart';
import 'package:clicli_md3/theme.dart';
import 'package:clicli_md3/ui/update_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows MD3 prompt, cancel, retry and real signed installer verification',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('CiliCiliWinRev 更新验证');
      await windowManager.setSize(const Size(960, 700));
      await windowManager.show();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final manifest = jsonDecode(
        await File('dist/update-0.7.0.json').readAsString(),
      );
      final installer = File('dist/CiliCiliWinRev-0.7.0-windows-x64-setup.exe');
      final root = await Directory.systemTemp.createTemp(
        'clicli-update-smoke-',
      );
      final boundary = GlobalKey();
      var transfers = 0, prepared = 0, shutdowns = 0;
      final firstStream = StreamController<List<int>>();
      final download = UpdateDownload(
        repository: 'WhiteBr1ck/CiliCiliWinRev',
        directoryFactory: () => root.createTemp('payload-'),
        validateInstallation: () async {},
        prepareInstallation: (path, hash, version) async {
          expect(await File(path).length(), await installer.length());
          expect(hash, manifest['sha256']);
          expect(version, '0.7.0');
          prepared++;
        },
        cancelInstallation: () async {},
        clientFactory: () => MockClient.streaming((request, _) async {
          if (request.url.host == 'raw.githubusercontent.com') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(manifest))),
              200,
            );
          }
          transfers++;
          return http.StreamedResponse(
            transfers == 1 ? firstStream.stream : installer.openRead(),
            200,
            contentLength: manifest['size'],
          );
        }),
      );
      download.shutdown = () async {
        shutdowns++;
      };
      final updates = AppUpdates(
        preferences,
        currentVersion: '0.6.1',
        download: download,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v0.7.0',
              'html_url':
                  'https://github.com/WhiteBr1ck/CiliCiliWinRev/releases/tag/v0.7.0',
              'assets': [
                {
                  'name': 'CiliCiliWinRev-0.7.0-windows-x64-setup.exe',
                  'size': manifest['size'],
                  'browser_download_url': manifest['url'],
                },
              ],
              'body': '应用内下载更新\n自动安装并重新打开',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), true);
      }

      Future<void> capture(String name) async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '.research/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      }

      try {
        // Development builds must not update the registered everyday installation.
        await expectLater(
          WindowsUpdater.validate(),
          throwsA(isA<PlatformException>()),
        );
        await expectLater(
          WindowsUpdater.commit(),
          throwsA(isA<PlatformException>()),
        );
        await updates.check();
      expect(updates.release, isNotNull, reason: '${updates.status}: ${updates.error}');
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AppTheme.make(Brightness.dark),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: FilledButton(
                      onPressed: () => showUpdateDialog(context, updates),
                      child: const Text('显示更新'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('显示更新'));
        await tester.pumpAndSettle();
        expect(find.text('立即更新'), findsOneWidget);
        expect(transfers, 0);
        await capture('update-dialog-0.7.0');
        await tester.tap(find.text('立即更新'));
        await until(() => transfers == 1);
        firstStream.add(List.filled(1048576, 0));
        await until(() => download.received == 1048576);
        expect(find.text('取消下载'), findsOneWidget);
        expect(prepared, 0);
        await capture('update-download-0.7.0');
        await tester.tap(find.text('取消下载'));
        await firstStream.close();
        await until(() => download.phase == DownloadPhase.idle);
        expect(shutdowns, 0);
        expect(await root.list().isEmpty, true);
        await tester.tap(find.text('立即更新'));
        await until(() => shutdowns == 1);
        expect(transfers, 2);
        expect(prepared, 1);
        expect(download.phase, DownloadPhase.installing);
        await File('.research/update-smoke-result.json').writeAsString(
          jsonEncode({
            'transfers': transfers,
            'prepared': prepared,
            'shutdowns': shutdowns,
            'signedInstallerVerified': true,
            'noAccountSessionLoaded': true,
            'nativeDevelopmentInstallRejected': true,
          }),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        updates.dispose();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}
