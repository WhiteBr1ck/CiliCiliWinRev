import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

/// Absolute broadcast instants from AniList; identity is matched before use.
class AiringSchedule {
  final http.Client client;
  AiringSchedule(this.client);
  static const query = r'''
    query($year:Int!,$season:MediaSeason!,$page:Int!) {
      Page(page:$page,perPage:50) {
        pageInfo { hasNextPage }
        media(type:ANIME,seasonYear:$year,season:$season,isAdult:false) {
          id title { native romaji english }
          nextAiringEpisode { airingAt episode }
          airingSchedule(perPage:1) { nodes { airingAt episode } }
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> load(int year, int quarter) async {
    final items = <Map<String, dynamic>>[];
    for (int page = 1; page <= 10; page++) {
      final r = await client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'CiliCiliWinRev/0.6.1',
            },
            body: jsonEncode({
              'query': query,
              'variables': {
                'year': year,
                'season': ['WINTER', 'SPRING', 'SUMMER', 'FALL'][quarter - 1],
                'page': page,
              },
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception('播出时间加载失败');
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final data = body['data']?['Page'];
      if (data == null) throw Exception('播出时间数据无效');
      items.addAll(
        (data['media'] as List).map((j) => Map<String, dynamic>.from(j)),
      );
      if (data['pageInfo']['hasNextPage'] != true) return items;
    }
    throw Exception('播出时间分页未完整返回');
  }

  static String normalize(String title) {
    var result = title.toLowerCase();
    // Preserve the season number, treating alternative season notation equally.
    result = result.replaceAllMapped(
      RegExp(r'第([一二三四五六七八九十\d]+)[季期]'),
      (m) =>
          'season${const {'一': '1', '二': '2', '三': '3', '四': '4', '五': '5', '六': '6', '七': '7', '八': '8', '九': '9', '十': '10'}[m[1]] ?? m[1]}',
    );
    result = result
        .replaceAll('シーズン', 'season')
        .replaceAll('season ', 'season');
    result = result
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('ⅱ', '2');
    return result.replaceAll(
      RegExp(r'[^a-z0-9\u3040-\u30ff\u4e00-\u9fff]'),
      '',
    );
  }

  static ScheduleEntry enrich(
    ScheduleEntry entry,
    List<Map<String, dynamic>> candidates,
  ) {
    // Movies/OVAs are release dates rather than a weekly television schedule.
    if (!['TV', 'WEB', ''].contains(entry.platform)) return entry;
    final names = {normalize(entry.originalName), normalize(entry.anime.name)}
      ..remove('');
    final matches = candidates
        .where(
          (j) =>
              (j['title'] as Map?)?.values.whereType<String>().any(
                (name) => names.contains(normalize(name)),
              ) ??
              false,
        )
        .toList();
    if (matches.length != 1) return entry;
    final match = matches.single;
    final nodes = match['airingSchedule']?['nodes'] as List? ?? [];
    final timestamp = number(
      match['nextAiringEpisode']?['airingAt'] ??
          (nodes.isEmpty ? null : nodes.first['airingAt']),
    );
    if (timestamp <= 0) return entry;
    final at = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    ).toLocal();
    final offset = at.timeZoneOffset;
    final hours = offset.inMinutes.abs() ~/ 60;
    final minutes = offset.inMinutes.abs() % 60;
    final zone =
        'UTC${offset.isNegative ? '-' : '+'}$hours${minutes == 0 ? '' : ':${minutes.toString().padLeft(2, '0')}'}';
    return ScheduleEntry(
      entry.anime,
      at.weekday,
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      weekdays: {at.weekday},
      premiere: entry.premiere,
      platform: entry.platform,
      originalName: entry.originalName,
      subjectId: entry.subjectId,
      continuing: entry.continuing,
      airingAt: at,
      timeSource: 'AniList · $zone',
      aliases: entry.aliases,
    );
  }
}
