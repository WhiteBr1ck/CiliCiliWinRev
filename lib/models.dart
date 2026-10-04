import 'dart:convert';

String cleanText(Object? value) => (value ?? '')
    .toString()
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

int number(Object? value) => double.tryParse('$value')?.toInt() ?? 0;
String displayStatus(Object? value) {
  final text = cleanText(value);
  final match = RegExp(r'^(\d+)\|(.+)$').firstMatch(text);
  if (match == null) return text;
  return '更新至第 ${match.group(1)} 集 · ${match.group(2)!.replaceFirst(RegExp(r'更$'), '更新')}';
}

class Anime {
  final int id, channel;
  final String name, image, backdrop, description, year, area, genres, status;
  final String director, actors;
  final double? score;
  final List<PlaySource> sources;
  final bool isFinished;
  const Anime({
    required this.id,
    required this.name,
    this.channel = 0,
    this.image = '',
    this.backdrop = '',
    this.description = '',
    this.year = '',
    this.area = '',
    this.genres = '',
    this.status = '',
    this.director = '',
    this.actors = '',
    this.score,
    this.sources = const [],
    this.isFinished = false,
  });

  factory Anime.fromJson(Map<String, dynamic> j) => Anime(
    id: number(j['vid'] ?? j['id']),
    channel: number(j['cid']),
    name: cleanText(j['vname'] ?? j['name']),
    image: '${j['thumbnail'] ?? j['pic'] ?? ''}',
    backdrop: '${j['img'] ?? ''}',
    description: cleanText(j['content']),
    year: '${j['year'] ?? ''}',
    area: cleanText(j['area']),
    genres: cleanText(j['type']),
    status: displayStatus(j['continu']),
    director: cleanText(j['director']),
    actors: cleanText(j['actor']),
    isFinished: number(j['isend']) == 1,
    score: double.tryParse('${j['gold']}'),
    sources: (j['parts'] as List? ?? [])
        .map((s) => PlaySource.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'cid': channel,
    'name': name,
    'pic': image,
    'img': backdrop,
    'content': description,
    'year': year,
    'area': area,
    'type': genres,
    'continu': status,
    'gold': score,
    'director': director,
    'actor': actors,
    'parts': sources.map((s) => s.toJson()).toList(),
    'isend': isFinished ? 1 : 0,
  };
  String get metadata => [
    year,
    area,
    genres.split(RegExp(r'[,， ]')).firstOrNull ?? '',
  ].where((s) => s.isNotEmpty).join(' · ');
}

class RecordPage<T> {
  final List<T> items;
  final int total;
  const RecordPage(this.items, this.total);
}

class AccountHistory {
  final int id;
  final WatchEntry entry;
  const AccountHistory(this.id, this.entry);
  factory AccountHistory.fromJson(Map<String, dynamic> j) => AccountHistory(
    number(j['vid']),
    WatchEntry(
      Anime.fromJson(j),
      '${j['play'] ?? ''}',
      '${j['part'] ?? ''}',
      number(j['time_point']),
      number(j['duration']),
      parseWatchDate(j['updated_at']) ?? parseWatchDate(j['created_at']),
    ),
  );
}

DateTime? parseWatchDate(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  final timestamp = num.tryParse(text);
  if (timestamp != null) {
    if (timestamp < 1000000000 || !timestamp.isFinite) return null;
    final milliseconds = timestamp > 100000000000
        ? timestamp
        : timestamp * 1000;
    if (milliseconds > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds.toInt(),
      isUtc: true,
    ).toLocal();
  }
  return DateTime.tryParse(text)?.toLocal();
}

class VodComment {
  final int id, likes;
  final String name, avatar, text, date, replyName;
  final bool liked;
  const VodComment({
    required this.id,
    required this.name,
    required this.text,
    this.avatar = '',
    this.date = '',
    this.replyName = '',
    this.likes = 0,
    this.liked = false,
  });
  factory VodComment.fromJson(Map<String, dynamic> j) => VodComment(
    id: number(j['id']),
    name: cleanText(j['uname']),
    text: cleanText(j['comments']),
    avatar: '${j['pic_url'] ?? ''}',
    date: '${j['created_at'] ?? ''}',
    replyName: cleanText(j['last_name']),
    likes: number(j['hits']),
    liked: j['islike'] == true,
  );
}

class ScheduleEntry {
  final Anime anime;
  final int weekday;
  final String time;
  final Set<int> weekdays;
  final DateTime? premiere;
  final String platform, originalName;
  final int? subjectId;
  final bool continuing;
  final DateTime? airingAt;
  final String timeSource;
  final List<String> aliases;
  const ScheduleEntry(
    this.anime,
    this.weekday,
    this.time, {
    this.weekdays = const {},
    this.premiere,
    this.platform = '',
    this.originalName = '',
    this.subjectId,
    this.continuing = false,
    this.airingAt,
    this.timeSource = '',
    this.aliases = const [],
  });
  bool occursOn(int day) =>
      weekdays.isEmpty ? weekday == day : weekdays.contains(day);
  static ScheduleEntry? parse(Anime anime) {
    final match = RegExp(
      r'(?:周|星期)([一二三四五六日天])\s*(\d{1,2}:\d{2})?',
    ).firstMatch('${anime.status}\n${anime.description}');
    if (match == null) return null;
    return ScheduleEntry(
      anime,
      match[1] == '天' ? 7 : '一二三四五六日'.indexOf(match[1]!) + 1,
      match[2] ?? '',
    );
  }
}

class TimetableBatch {
  final List<ScheduleEntry> items;
  final bool hasMore;
  const TimetableBatch(this.items, {this.hasMore = false});
}

class DanmakuEntry {
  final int id, color;
  final int type;
  final String size;
  final double time;
  final String text;
  const DanmakuEntry(
    this.id,
    this.time,
    this.text,
    this.color, {
    this.type = 0,
    this.size = 'M',
  });
  static DanmakuEntry? parse(Map<String, dynamic> j) {
    final time = double.tryParse('${j['time_point']}');
    if (time == null || !time.isFinite || time < 0) return null;
    dynamic content = j['content'];
    if (content is String) {
      try {
        content = jsonDecode(content);
      } catch (_) {}
    }
    final text = cleanText(content is Map ? content['content'] : content);
    if (text.isEmpty) return null;
    return DanmakuEntry(
      number(j['id']),
      time,
      text,
      content is Map && content['color'] != null
          ? number(content['color'])
          : 0xFFFFFFFF,
      type: content is Map ? number(content['type']).clamp(0, 2) : 0,
      size: content is Map ? '${content['size'] ?? 'M'}' : 'M',
    );
  }
}

class PlaySource {
  final String id, name;
  final List<String> episodes;
  const PlaySource(this.id, this.name, this.episodes);
  factory PlaySource.fromJson(Map<String, dynamic> j) => PlaySource(
    '${j['play']}',
    cleanText(j['play_zh'] ?? j['play']),
    (j['part'] as List? ?? []).map((x) => '$x').toList(),
  );
  Map<String, dynamic> toJson() => {
    'play': id,
    'play_zh': name,
    'part': episodes,
  };
}

class Channel {
  final int id;
  final String name;
  final List<String> genres, years, areas;
  const Channel(
    this.id,
    this.name, {
    this.genres = const [],
    this.years = const [],
    this.areas = const [],
  });
  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
    number(j['id']),
    cleanText(j['name']),
    genres: (j['types'] as List? ?? [])
        .map((x) => '$x')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList(),
    years: (j['years'] as List? ?? [])
        .map((x) => '$x')
        .where((s) => s.isNotEmpty)
        .toList(),
    areas: (j['areas'] as List? ?? [])
        .map((x) => '$x')
        .where((s) => s.isNotEmpty)
        .toList(),
  );
}

class CatalogPage {
  final List<Anime> items;
  final int total;
  const CatalogPage(this.items, this.total);
}

class Playable {
  final String name, url;
  final Map<String, String> headers;
  const Playable(this.name, this.url, [this.headers = const {}]);
}

class WatchEntry {
  final Anime anime;
  final String source, episode;
  final int position, duration;
  final DateTime? updated;
  const WatchEntry(
    this.anime,
    this.source,
    this.episode,
    this.position,
    this.duration,
    this.updated,
  );
  factory WatchEntry.fromJson(Map<String, dynamic> j) => WatchEntry(
    Anime.fromJson(Map<String, dynamic>.from(j['anime'])),
    '${j['source']}',
    '${j['episode']}',
    number(j['position']),
    number(j['duration']),
    parseWatchDate(j['updated']),
  );
  Map<String, dynamic> toJson() => {
    'anime': anime.toJson(),
    'source': source,
    'episode': episode,
    'position': position,
    'duration': duration,
    'updated': updated?.toIso8601String(),
  };
  double get progress => duration > 0 ? (position / duration).clamp(0, 1) : 0;
}
