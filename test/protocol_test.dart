import 'dart:convert';
import 'dart:io';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'quarter loading never reads CLICLI catalog or per-title availability',
    () async {
      final api = ClicliApi(
        client: MockClient((r) async {
          expect(r.url.host, isNot('example.com'));
          if (r.url.host == 'graphql.anilist.co') {
            return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({
              'total': 1,
              'limit': 20,
              'data': [
                {
                  'id': 7,
                  'date': '2025-10-01',
                  'name_cn': '未收录作品',
                  'platform': 'TV',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..host = 'https://example.com';
      final rows = await api.timetable(2025, quarter: 4);
      expect(rows.items.single.anime.name, '未收录作品');
      expect(rows.items.single.anime.id, lessThan(0));
      api.dispose();
    },
  );
  test(
    'decrypts independently generated RSA / AES response including Chinese',
    () async {
      final api = ClicliApi();
      await api.loadProtocol();
      final result = api.decodeResponse(
        File('test/fixtures/encrypted_response.txt').readAsStringSync(),
      );
      expect(result['code'], 20000);
      expect(result['data'], {'name': '测试番剧', 'id': 42});
      api.dispose();
    },
  );
  test(
    'Authentication matches the original timestamp and base64 protocol',
    () async {
      final api = ClicliApi();
      await api.loadProtocol();
      final now = DateTime.fromMillisecondsSinceEpoch(1234567890);
      final headers = api.headers(now: now);
      final cipher = enc.Encrypter(
        enc.AES(
          enc.Key.fromUtf8('ziISjqkXPsGUMRNGyWigxDGtJbfTdcGv'),
          mode: enc.AESMode.cbc,
        ),
      );
      final text = utf8.decode(
        base64.decode(
          cipher.decrypt64(
            headers['Authentication']!,
            iv: enc.IV.fromUtf8('WonrnVkxeIxDcFbv'),
          ),
        ),
      );
      expect(text, '1.1.5-1234567890-3-1.0.0-win32');
      expect(headers['system'], '3');
      api.dispose();
    },
  );
  test(
    'encodes search input and surfaces API errors without empty results',
    () async {
      final api = ClicliApi(
        client: MockClient((req) async {
          expect(req.url.queryParameters['key'], 'Re：从零 & 第四季');
          return http.Response(
            jsonEncode({'code': 500252, 'message': '影片不存在'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..host = 'https://example.com';
      await api.loadProtocol();
      expect(
        () => api.search('Re：从零 & 第四季'),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', '影片不存在'),
        ),
      );
      api.dispose();
    },
  );
  test('resolves supported provider template without running Lua', () async {
    final calls = <Uri>[];
    final api = ClicliApi(
      client: MockClient((req) async {
        calls.add(req.url);
        if (req.url.path == '/pc/video/play') {
          return http.Response(
            jsonEncode({
              'code': 20000,
              'data': [
                {
                  'url': 'test_code_h265',
                  'vip_type': 0,
                  'ps': 1,
                  'parse':
                      'local uri = "https://example.com/app/playaddr/lua/v4/get?vcode="..source\nlocal appId = "id"\nlocal appKey = "key"',
                },
              ],
            }),
            200,
          );
        }
        expect(req.url.queryParameters['vcode'], 'test_code_h265');
        expect(req.headers['appid'], 'id');
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'playAddr': [
                {
                  'desc': '1080P',
                  'm3u8FileDomain': 'https://example.com',
                  'addr': '/video.m3u8',
                },
              ],
            },
          }),
          200,
        );
      }),
    )..host = 'https://example.com';
    await api.loadProtocol();
    final resolved = await api.resolve(42, 'mao', '第01集');
    expect(resolved.single.url, 'https://example.com/video.m3u8');
    expect(calls.length, 2);
    api.dispose();
  });
}
