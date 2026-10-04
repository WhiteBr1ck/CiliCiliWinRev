import 'dart:convert';
import 'package:clicli_md3/services/season_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'quarter loads all pages, preserves unknown days and multiple weekdays',
    () async {
      final offsets = <int>[];
      final client = MockClient((r) async {
        expect(r.headers.containsKey('x-token'), false);
        if (r.url.host == 'graphql.anilist.co') return http.Response('{}', 503);
        final body = jsonDecode(r.body);
        expect(body['filter']['air_date'], ['>=2025-10-01', '<2026-01-01']);
        final offset = int.parse(r.url.queryParameters['offset']!);
        offsets.add(offset);
        return http.Response(
          jsonEncode({
            'total': 45,
            'limit': 20,
            'data': [
              for (int i = offset; i < offset + 20 && i < 45; i++)
                {
                  'id': i + 1,
                  'date': '2025-10-02',
                  'name': 'Original $i',
                  'name_cn': '作品$i',
                  'platform': 'TV',
                  'infobox': i == 0
                      ? [
                          {'key': '放送星期', 'value': '星期四、星期日'},
                          {'key': '放送时间', 'value': '23:30'},
                        ]
                      : [],
                },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = SeasonSchedule(client);
      final items = await service.load(2025, 4);
      expect(offsets, unorderedEquals([0, 20, 40]));
      expect(items, hasLength(45));
      expect(items.first.weekdays, {4, 7});
      expect(items.first.occursOn(7), true);
      expect(items.first.time, '23:30');
      expect(items[1].weekday, 0);
      expect(items[1].subjectId, 2);
      await service.load(2025, 4);
      expect(offsets, hasLength(3));
      client.close();
    },
  );
  test(
    'current-quarter calendar includes continuing series without dropping unknowns',
    () async {
      final now = DateTime.now();
      final quarter = (now.month - 1) ~/ 3 + 1;
      final start = DateTime(now.year, (quarter - 1) * 3 + 1);
      final old = start
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('T')
          .first;
      final current = start.toIso8601String().split('T').first;
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.method == 'GET'
                ? [
                    {
                      'weekday': {'id': 1},
                      'items': [
                        {'id': 2, 'air_date': old, 'name_cn': '续播作品'},
                      ],
                    },
                  ]
                : {
                    'total': 1,
                    'limit': 20,
                    'data': [
                      {
                        'id': 1,
                        'date': current,
                        'name_cn': '新作',
                        'platform': 'WEB',
                      },
                    ],
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final items = await SeasonSchedule(client).load(now.year, quarter);
      expect(items, hasLength(2));
      expect(items.first.continuing, true);
      expect(items.first.occursOn(1), true);
      expect(items.last.weekday, 0);
      client.close();
    },
  );
  test(
    'failed later pages report failure instead of presenting an incomplete quarter',
    () async {
      final client = MockClient(
        (r) async => http.Response(
          r.url.queryParameters['offset'] == '0'
              ? jsonEncode({'total': 25, 'limit': 20, 'data': []})
              : '{}',
          r.url.queryParameters['offset'] == '0' ? 200 : 503,
        ),
      );
      await expectLater(SeasonSchedule(client).load(2025, 1), throwsException);
      client.close();
    },
  );
}
