import 'dart:convert';
import 'package:clicli_md3/services/app_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> release({
  String version = '0.7.0',
  bool asset = true,
  String host = 'github.com',
}) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'html_url':
      'https://github.com/WhiteBr1ck/CiliCiliWinRev/releases/tag/v$version',
  'assets': [
    if (asset)
      {
        'name': 'CiliCiliWinRev-$version-windows-x64-setup.exe',
        'size': 51000000,
        'browser_download_url':
            'https://$host/WhiteBr1ck/CiliCiliWinRev/releases/download/v$version/CiliCiliWinRev-$version-windows-x64-setup.exe',
      },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'numeric release version comparison excludes prereleases and invalid tags',
    () {
      expect(AppUpdates.isNewer('v0.10.0', '0.6.0'), true);
      expect(AppUpdates.isNewer('0.6.0', '0.6.0'), false);
      expect(AppUpdates.isNewer('0.5.9', '0.6.0'), false);
      expect(AppUpdates.isNewer('1.0.0-beta', '0.6.0'), false);
      expect(AppUpdates.isNewer('latest', '0.6.0'), false);
    },
  );
  test(
    'public update check uses repository and installer without account headers',
    () async {
      final updates = AppUpdates(
        await SharedPreferences.getInstance(),
        currentVersion: '0.6.1',
        client: MockClient((r) async {
          expect(
            r.url.toString(),
            'https://api.github.com/repos/WhiteBr1ck/CiliCiliWinRev/releases/latest',
          );
          expect(r.headers.containsKey('x-token'), false);
          expect(r.headers.containsKey('authorization'), false);
          return http.Response(jsonEncode(release()), 200);
        }),
      );
      await updates.check();
      expect(updates.status, UpdateStatus.available);
      expect(updates.release!.version, '0.7.0');
      expect(
        updates.release!.installer.path,
        endsWith('0.7.0-windows-x64-setup.exe'),
      );
      updates.dispose();
    },
  );
  test(
    'automatic preference persists; manual checks still work and concurrent calls share a request',
    () async {
      var requests = 0;
      final prefs = await SharedPreferences.getInstance();
      final updates = AppUpdates(
        prefs,
        currentVersion: '0.6.1',
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(release(version: '0.6.1')), 200);
        }),
      );
      await updates.setAutomatic(false);
      await updates.check(startup: true);
      expect(requests, 0);
      expect(prefs.getBool('automaticUpdates'), false);
      await Future.wait([updates.check(), updates.check()]);
      expect(requests, 1);
      expect(updates.status, UpdateStatus.current);
      updates.dispose();
    },
  );
  test(
    'empty Releases and API rate limits remain distinct from up-to-date',
    () async {
      var code = 404;
      final updates = AppUpdates(
        await SharedPreferences.getInstance(),
        currentVersion: '0.6.1',
        client: MockClient((_) async => http.Response('{}', code)),
      );
      await updates.check();
      expect(updates.status, UpdateStatus.noRelease);
      code = 403;
      await updates.check();
      expect(updates.status, UpdateStatus.failed);
      expect(updates.label, contains('请求受限'));
      updates.dispose();
    },
  );
  test(
    'missing installer, foreign download and prerelease are rejected',
    () async {
      var data = release(asset: false);
      final updates = AppUpdates(
        await SharedPreferences.getInstance(),
        currentVersion: '0.6.1',
        client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
      );
      await updates.check();
      expect(updates.status, UpdateStatus.failed);
      expect(updates.release, isNull);
      data = release(host: 'example.com');
      await updates.check();
      expect(updates.status, UpdateStatus.failed);
      data = {...release(), 'prerelease': true};
      await updates.check();
      expect(updates.status, UpdateStatus.failed);
      updates.dispose();
    },
  );
}
