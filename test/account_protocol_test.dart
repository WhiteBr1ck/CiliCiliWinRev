import 'dart:convert';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> decryptRequest(String body) {
  final parts = body.split('.');
  expect(parts.length, 2);
  expect(base64Decode(parts.first).length, 256);
  const key = 'R5xThLNmXbpDOgyj';
  final aes = enc.Encrypter(
    enc.AES(enc.Key.fromUtf8(key), mode: enc.AESMode.cbc),
  );
  return jsonDecode(
    aes.decrypt64(
      parts.last,
      iv: enc.IV.fromUtf8(key.split('').reversed.join()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'encrypted login, registration and code requests match original fields',
    () async {
      final seen = <http.Request>[];
      final api = ClicliApi(
        client: MockClient((r) async {
          seen.add(r);
          return http.Response(
            jsonEncode({
              'code': 20000,
              'data': {'token': 'fixture'},
            }),
            200,
          );
        }),
      )..host = 'https://example.com';
      await api.loadProtocol();
      await api.login('test@example.com', '仅用于测试');
      expect(decryptRequest(seen.last.body), {
        'enum': 1,
        'email': 'test@example.com',
        'phone': '',
        'password': '仅用于测试',
        'symbol': 'win32',
      });
      await api.register(
        nickname: '昵称',
        email: 'test@example.com',
        password: '123456',
        code: '1234',
      );
      expect(decryptRequest(seen.last.body), {
        'user_name': '昵称',
        'email': 'test@example.com',
        'password': '123456',
        'smscode': '1234',
        'enum': 1,
        'phone': '',
      });
      await api.sendCode('test@example.com', 'Reg', uuid: 'u', dots: '7');
      expect(decryptRequest(seen.last.body), {
        'email': 'test@example.com',
        'type': 'Reg',
        'enum': 1,
        'uuid': 'u',
        'dots': '7',
      });
      await api.loginWithCode('test@example.com', '1234');
      expect(decryptRequest(seen.last.body), {
        'email': 'test@example.com',
        'code': '1234',
      });
      for (final r in seen) {
        expect(r.method, 'POST');
        expect(r.body.contains('test@example.com'), false);
      }
      api.dispose();
    },
  );
  test(
    'token, cloud history, deletes and comment mutations use verified wire fields',
    () async {
      late http.Request seen;
      final api =
          ClicliApi(
              client: MockClient((r) async {
                seen = r;
                return http.Response(
                  jsonEncode({'code': 20000, 'data': {}}),
                  200,
                );
              }),
            )
            ..host = 'https://example.com'
            ..token = 'fixture';
      await api.loadProtocol();
      await api.saveAccountHistory(
        WatchEntry(
          const Anime(id: 42, name: '测试'),
          'mao',
          '第02集',
          75,
          100,
          DateTime(2026),
        ),
      );
      expect(seen.headers['X-Token'] ?? seen.headers['x-token'], 'fixture');
      expect(decryptRequest(seen.body), {
        'type': 'post',
        'vid': 42,
        'play': 'mao',
        'part': '第02集',
        'time_point': 75,
      });
      await api.deleteAccountHistory(42);
      expect(seen.method, 'DELETE');
      expect(decryptRequest(seen.body), {
        'ids': [42],
      });
      await api.postComment(42, '评论', lastId: 7, uuid: 'u', dots: '6');
      expect(decryptRequest(seen.body), {
        'vid': 42,
        'comments': '评论',
        'last_id': 7,
        'uuid': 'u',
        'dots': '6',
      });
      await api.likeComment(42, const VodComment(id: 7, name: 'n', text: 't'));
      expect(decryptRequest(seen.body)['like'], true);
      api.dispose();
    },
  );
  test(
    'whole-episode danmaku reads and sends original time and style fields',
    () async {
      late http.Request seen;
      final api = ClicliApi(
        client: MockClient((r) async {
          seen = r;
          return http.Response(
            jsonEncode({
              'code': 20000,
              'data': {
                'items': [
                  {
                    'id': 7,
                    'time_point': 128,
                    'content':
                        '{"content":"后续弹幕","type":1,"size":"S","color":4294967295}',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..host = 'https://example.com';
      await api.loadProtocol();
      final rows = await api.danmaku(42, 'mao', '第01集', 0, end: 600);
      expect(seen.url.queryParameters['end_time_point'], '600');
      final entry = DanmakuEntry.parse(rows.single)!;
      expect(entry.time, 128);
      expect(entry.type, 1);
      expect(entry.size, 'S');
      await api.sendDanmaku(
        42,
        'mao',
        '第01集',
        128.75,
        '新弹幕',
        color: 0xFFFFD166,
        type: 2,
        size: 'S',
        uuid: 'u',
        dots: '8',
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/pc/danmu');
      final body = decryptRequest(seen.body);
      expect(body['time_point'], 128);
      expect(body['type'], 'put');
      expect(jsonDecode(body['content']), {
        'content': '新弹幕',
        'color': 0xFFFFD166,
        'type': 2,
        'size': 'S',
      });
      expect(body['uuid'], 'u');
      expect(body['dots'], '8');
      api.dispose();
    },
  );
  test(
    'session expiry clears token and captcha errors retain challenge',
    () async {
      var expired = false;
      final api =
          ClicliApi(
              client: MockClient(
                (r) async => http.Response(
                  jsonEncode({'code': 50014, 'message': '登录失效'}),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                ),
              ),
            )
            ..host = 'https://example.com'
            ..token = 'fixture'
            ..onSessionExpired = () {
              expired = true;
            };
      await api.loadProtocol();
      await expectLater(
        api.userInfo(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 50014)),
      );
      expect(expired, true);
      expect(api.token, isNull);
      api.dispose();
      final challenge = ClicliApi(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'code': 429101,
              'message': 'challenge required',
              'data': {'uuid': 'u', 'image_base64': 'fixture'},
            }),
            200,
          ),
        ),
      )..host = 'https://example.com';
      await challenge.loadProtocol();
      await expectLater(
        challenge.sendCode('test@example.com', 'Reg'),
        throwsA(
          isA<ApiException>().having((e) => e.data?['uuid'], 'uuid', 'u'),
        ),
      );
      challenge.dispose();
    },
  );
  test('danmaku timestamps preserve decimals and reject invalid times', () {
    expect(
      DanmakuEntry.parse({
        'id': 1,
        'time_point': '12.75',
        'content': '{"content":"测试","color":4294967295}',
      })?.time,
      12.75,
    );
    expect(
      DanmakuEntry.parse({'time_point': 'invalid', 'content': '测试'}),
      isNull,
    );
    expect(DanmakuEntry.parse({'content': '测试'}), isNull);
    expect(DanmakuEntry.parse({'time_point': -1, 'content': '测试'}), isNull);
    expect(DanmakuEntry.parse({'time_point': 0, 'content': '测试'})?.time, 0);
  });
  test('timetable parses stated metadata without inventing times', () {
    expect(
      ScheduleEntry.parse(
        const Anime(id: 1, name: 'a', status: '更新至第8集 · 周日23:00更新'),
      )?.weekday,
      7,
    );
    expect(
      ScheduleEntry.parse(
        const Anime(id: 1, name: 'a', description: '周天更新'),
      )?.weekday,
      7,
    );
    expect(
      ScheduleEntry.parse(
        const Anime(id: 1, name: 'a', description: '周五11:00更'),
      )?.time,
      '11:00',
    );
    expect(
      ScheduleEntry.parse(
        const Anime(id: 1, name: 'a', description: '星期二更新'),
      )?.time,
      '',
    );
    expect(ScheduleEntry.parse(const Anime(id: 1, name: 'a')), isNull);
  });
  test('cloud history uses video ID instead of record ID', () {
    final h = AccountHistory.fromJson({
      'id': 99,
      'vid': 42,
      'name': '测试',
      'play': 'mao',
      'part': '第03集',
      'time_point': 123,
    });
    expect(h.id, 42);
    expect(h.entry.anime.id, 42);
    expect(h.entry.position, 123);
    expect(h.entry.updated, isNull);
  });
  test(
    'history parses ISO offsets, Unix seconds and milliseconds without fabricated dates',
    () {
      final iso = AccountHistory.fromJson({
        'updated_at': '2026-10-04T23:30:00+08:00',
      }).entry.updated!;
      expect(iso.toUtc(), DateTime.utc(2026, 10, 4, 15, 30));
      expect(parseWatchDate(iso.millisecondsSinceEpoch ~/ 1000), iso);
      expect(parseWatchDate('${iso.millisecondsSinceEpoch}'), iso);
      expect(parseWatchDate('invalid'), isNull);
      expect(parseWatchDate(null), isNull);
      expect(
        AccountHistory.fromJson({
          'updated_at': 'invalid',
          'created_at': '2026-10-03T01:00:00Z',
        }).entry.updated?.toUtc(),
        DateTime.utc(2026, 10, 3, 1),
      );
    },
  );
}
