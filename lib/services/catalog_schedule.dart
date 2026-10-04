import '../models.dart';
import 'cover_cache.dart';

typedef ScheduleSearch =
    Future<CatalogPage> Function(String keyword, {int page});

/// Resolves only the selected public schedule entry to a playable catalog item.
class CatalogSchedule {
  final ScheduleSearch search;
  final Future<Anime> Function(int) detail;
  final _cache = <String, ({DateTime at, Anime? anime})>{};
  final _pending = <String, Future<Anime?>>{};
  CatalogSchedule({required this.search, required this.detail});

  static String _nameKey(String name) =>
      '${CoverCache.normalize(name)}|${CoverCache.season(name).isEmpty ? '1' : CoverCache.season(name)}';

  static bool matches(ScheduleEntry entry, Anime anime) {
    final expectedYear = entry.premiere?.year.toString() ?? entry.anime.year;
    if (expectedYear.isNotEmpty && anime.year != expectedYear) return false;
    return [entry.anime.name, entry.originalName, ...entry.aliases]
        .where((n) => n.isNotEmpty)
        .any((name) => _nameKey(name) == _nameKey(anime.name));
  }

  static String keyword(String name) {
    if (name == '航海王') return '海贼王';
    final base = name.replaceAll(RegExp(r'第[一二三四五六七八九十\d]+[季期]|最终季|最終季'), '');
    final chinese =
        RegExp(
            r'[\u4e00-\u9fff]{3,}',
          ).allMatches(base).map((m) => m[0]!).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return chinese.isNotEmpty ? chinese.first : base.trim();
  }

  String _key(ScheduleEntry entry) =>
      '${entry.subjectId}|${entry.anime.name}|${entry.premiere?.year ?? entry.anime.year}|${entry.aliases.join('|')}';

  Future<Anime?> resolve(ScheduleEntry entry) {
    final key = _key(entry), cached = _cache[_key(entry)];
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 15) {
      return Future.value(cached.anime);
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final anime = await _resolve(entry);
        _cache[key] = (at: DateTime.now(), anime: anime);
        return anime;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<Anime?> _resolve(ScheduleEntry entry) async {
    final queries = {
      keyword(entry.anime.name),
      keyword(entry.originalName),
      ...entry.aliases.map(keyword),
    }..remove('');
    final checked = <int>{};
    for (final query in queries) {
      final seen = <int>{};
      for (int page = 1; ; page++) {
        final result = await search(query, page: page);
        final added = result.items.where((a) => seen.add(a.id)).toList();
        if (added.isEmpty) break;
        for (final candidate in added) {
          if (matches(entry, candidate) && checked.add(candidate.id)) {
            final anime = await detail(candidate.id);
            if (matches(entry, anime) &&
                anime.sources.any((s) => s.episodes.isNotEmpty)) {
              return anime;
            }
          }
        }
        if (seen.length >= result.total) break;
        // Do not report absence when a broad query was not fully read.
        if (page >= 10) throw StateError('搜索结果过多，请重试或在片库搜索作品名称');
      }
    }
    return null;
  }

  void invalidate(ScheduleEntry entry) => _cache.remove(_key(entry));
}
