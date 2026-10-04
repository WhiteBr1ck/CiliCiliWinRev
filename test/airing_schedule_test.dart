import 'dart:convert';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/airing_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'broadcast pagination uses public requests and converts UTC including day rollover',
    () async {
      final at = DateTime.utc(2026, 10, 5, 18, 30);
      final pages = <int>[];
      final client = MockClient((r) async {
        expect(r.headers.containsKey('x-token'), false);
        final vars = jsonDecode(r.body)['variables'];
        expect(vars['season'], 'FALL');
        pages.add(vars['page']);
        return http.Response(
          jsonEncode({
            'data': {
              'Page': {
                'pageInfo': {'hasNextPage': vars['page'] == 1},
                'media': vars['page'] == 1
                    ? [
                        {
                          'id': 1,
                          'title': {'native': '魔法少女育成計画 restart'},
                          'nextAiringEpisode': {
                            'airingAt': at.millisecondsSinceEpoch ~/ 1000,
                          },
                        },
                      ]
                    : [],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final rows = await AiringSchedule(client).load(2026, 4);
      final entry = AiringSchedule.enrich(
        const ScheduleEntry(
          Anime(id: 1, name: '魔法少女育成计划 restart'),
          1,
          '',
          originalName: '魔法少女育成計画 restart',
          platform: 'TV',
        ),
        rows,
      );
      final local = at.toLocal();
      expect(pages, [1, 2]);
      expect(entry.airingAt, local);
      expect(entry.weekday, local.weekday);
      expect(entry.weekdays, {local.weekday});
      expect(
        entry.time,
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
      );
      expect(entry.timeSource, startsWith('AniList · UTC'));
      client.close();
    },
  );
  test(
    'season spelling is equivalent, other seasons and ambiguous titles stay unknown',
    () {
      const entry = ScheduleEntry(
        Anime(id: 1, name: '第二季'),
        1,
        '',
        originalName: '作品 第2期',
        platform: 'TV',
      );
      final rows = [
        {
          'title': {'native': '作品 Season2'},
          'airingSchedule': {
            'nodes': [
              {'airingAt': 1791219600},
            ],
          },
        },
      ];
      expect(AiringSchedule.enrich(entry, rows).time, isNotEmpty);
      expect(AiringSchedule.enrich(entry, [...rows, ...rows]).time, isEmpty);
      expect(
        AiringSchedule.enrich(entry, [
          {
            'title': {'native': '作品 Season3'},
          },
        ]).time,
        isEmpty,
      );
      expect(
        AiringSchedule.enrich(entry, [
          {
            'title': {'native': '作品 Season2'},
          },
        ]).time,
        isEmpty,
      );
    },
  );
}
