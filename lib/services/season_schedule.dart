import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import 'airing_schedule.dart';

/// Quarter metadata is independent of whether CLICLI has indexed the work.
class SeasonSchedule {
  final http.Client client;
  final _cache = <String, ({DateTime at, List<ScheduleEntry> items})>{};
  SeasonSchedule(this.client);
  static const headers = {
    'User-Agent': 'CiliCiliWinRev/0.6.1 (https://clicli.blog/)',
    'Content-Type': 'application/json',
  };
  Future<List<ScheduleEntry>> load(int year, int quarter) async {
    if (quarter < 1 || quarter > 4) throw ArgumentError.value(quarter);
    final key = '$year-$quarter';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 30) {
      return cached.items;
    }
    final start = DateTime(year, (quarter - 1) * 3 + 1);
    final end = DateTime(year, quarter * 3 + 1);
    String date(DateTime d) => d.toIso8601String().split('T').first;
    final body = jsonEncode({
      'keyword': '',
      'sort': 'rank',
      'filter': {
        'type': [2],
        'air_date': ['>=${date(start)}', '<${date(end)}'],
        'nsfw': false,
      },
    });
    Future<Map<String, dynamic>> page(int offset) async {
      final response = await client
          .post(
            Uri.parse(
              'https://api.bgm.tv/v0/search/subjects?limit=20&offset=$offset',
            ),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('季度目录加载失败（HTTP ${response.statusCode}）');
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    final first = await page(0);
    final total = number(first['total']), limit = number(first['limit']);
    if (limit <= 0 || total > 10000) throw Exception('季度目录分页数据无效');
    final records = <Map<String, dynamic>>[
      for (final j in first['data'] as List) Map<String, dynamic>.from(j),
    ];
    for (int offset = limit; offset < total; offset += limit * 3) {
      final pages = await Future.wait([
        for (int p = offset; p < offset + limit * 3 && p < total; p += limit)
          page(p),
      ]);
      for (final result in pages) {
        final list = result['data'] as List;
        if (list.isEmpty) throw Exception('季度目录未完整返回，请刷新重试');
        records.addAll(list.map((j) => Map<String, dynamic>.from(j)));
      }
    }
    if (records.length < total) throw Exception('季度目录未完整返回，请刷新重试');
    final calendar = <int, Set<int>>{};
    final now = DateTime.now();
    if (now.year == year && (now.month - 1) ~/ 3 + 1 == quarter) {
      try {
        final response = await client
            .get(Uri.parse('https://api.bgm.tv/calendar'), headers: headers)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          for (final day
              in jsonDecode(utf8.decode(response.bodyBytes)) as List) {
            final weekday = number(day['weekday']['id']);
            for (final subject in day['items'] as List) {
              calendar
                  .putIfAbsent(number(subject['id']), () => {})
                  .add(weekday);
              final date = DateTime.tryParse('${subject['air_date']}');
              if (date != null &&
                  date.isBefore(start) &&
                  !records.any(
                    (j) => number(j['id']) == number(subject['id']),
                  )) {
                records.add({
                  ...Map<String, dynamic>.from(subject),
                  'date': '${subject['air_date']}',
                  'platform': cleanText(subject['platform']),
                  '_continuing': true,
                });
              }
            }
          }
        }
      } catch (_) {
        // Per-subject infobox remains available if the current calendar fails.
      }
    }
    final unique = <int, ScheduleEntry>{};
    for (final j in records) {
      final id = number(j['id']);
      if (id <= 0) continue;
      final premiere = DateTime.tryParse('${j['date']}');
      if (premiere == null ||
          premiere.isBefore(start) && j['_continuing'] != true ||
          !premiere.isBefore(end)) {
        continue;
      }
      final weekdays = <int>{};
      var time = '';
      for (final field in j['infobox'] as List? ?? []) {
        if ('${field['key']}'.contains('星期')) {
          for (final match in RegExp(
            r'(?:周|星期)([一二三四五六日天])',
          ).allMatches('${field['value']}')) {
            weekdays.add(
              match[1] == '天' ? 7 : '一二三四五六日'.indexOf(match[1]!) + 1,
            );
          }
        }
        if ('${field['key']}'.contains('时间')) {
          time =
              RegExp(
                r'\b\d{1,2}:\d{2}\b',
              ).firstMatch('${field['value']}')?[0] ??
              time;
        }
      }
      weekdays.addAll(calendar[id] ?? {});
      final originalName = cleanText(j['name']);
      final name = cleanText(j['name_cn']);
      final images = j['images'] is Map ? j['images'] as Map : const {};
      final aliases = <String>[];
      for (final field in j['infobox'] as List? ?? []) {
        if (field['key'] == '别名') {
          final value = field['value'];
          if (value is List) {
            aliases.addAll(
              value.whereType<Map>().map((a) => cleanText(a['v'])),
            );
          } else if (value is String) {
            aliases.add(cleanText(value));
          }
        }
      }
      unique[id] = ScheduleEntry(
        Anime(
          id: -id,
          name: name.isEmpty ? originalName : name,
          image: '${images['common'] ?? images['large'] ?? ''}'.replaceFirst(
            'http:',
            'https:',
          ),
          year: '$year',
          description: cleanText(j['summary']),
          status: cleanText(j['platform']),
        ),
        weekdays.isEmpty ? 0 : weekdays.first,
        time,
        weekdays: weekdays,
        premiere: premiere,
        platform: cleanText(j['platform']),
        originalName: originalName,
        subjectId: id,
        continuing: j['_continuing'] == true,
        timeSource: time.isEmpty ? '' : 'Bangumi · 原站时间',
        aliases: aliases,
      );
    }
    var items = unique.values.toList()
      ..sort((a, b) {
        final order = a.premiere!.compareTo(b.premiere!);
        return order != 0 ? order : a.subjectId!.compareTo(b.subjectId!);
      });
    try {
      final airing = AiringSchedule(client);
      final candidates = await airing.load(year, quarter);
      if (items.any((e) => e.continuing)) {
        final previousYear = quarter == 1 ? year - 1 : year;
        final previousQuarter = quarter == 1 ? 4 : quarter - 1;
        try {
          candidates.addAll(await airing.load(previousYear, previousQuarter));
        } catch (_) {}
      }
      items = items.map((e) => AiringSchedule.enrich(e, candidates)).toList();
    } catch (_) {
      // A secondary service failure must not hide the complete quarter catalog.
    }
    _cache[key] = (at: DateTime.now(), items: items);
    return items;
  }

  void invalidate(int year, int quarter) => _cache.remove('$year-$quarter');
}
