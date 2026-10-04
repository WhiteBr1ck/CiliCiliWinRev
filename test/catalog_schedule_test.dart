import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/catalog_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const entry = ScheduleEntry(
    Anime(id: -1, name: '作品 第二季', year: '2026'),
    1,
    '22:30',
  );
  test(
    'selected title resolves correct season with episodes and caches the result',
    () async {
      var searches = 0;
      final service = CatalogSchedule(
        search: (_, {int page = 1}) async {
          searches++;
          return const CatalogPage([
            Anime(id: 2, name: '作品第三季', year: '2026'),
            Anime(id: 1, name: '作品第二季', year: '2026'),
          ], 2);
        },
        detail: (id) async => const Anime(
          id: 1,
          name: '作品第二季',
          year: '2026',
          sources: [
            PlaySource('mao', '高速云', ['第01集']),
          ],
        ),
      );
      expect(searches, 0);
      final anime = await service.resolve(entry);
      expect(anime!.id, 1);
      expect(anime.sources.single.episodes, ['第01集']);
      await service.resolve(entry);
      expect(searches, 1);
      service.invalidate(entry);
      await service.resolve(entry);
      expect(searches, 2);
    },
  );
  test('absent titles and titles without episodes return null', () async {
    final empty = CatalogSchedule(
      search: (_, {int page = 1}) async => const CatalogPage([], 0),
      detail: (_) async => throw StateError('unexpected detail'),
    );
    expect(await empty.resolve(entry), isNull);
    final noEpisodes = CatalogSchedule(
      search: (_, {int page = 1}) async =>
          const CatalogPage([Anime(id: 1, name: '作品第二季', year: '2026')], 1),
      detail: (_) async => const Anime(id: 1, name: '作品第二季', year: '2026'),
    );
    expect(await noEpisodes.resolve(entry), isNull);
  });
  test(
    'aliases preserve part and year; network errors are retriable',
    () async {
      const alias = ScheduleEntry(
        Anime(id: -1, name: '别名', year: '2026'),
        1,
        '',
        aliases: ['作品 第2季 Part.2'],
      );
      expect(
        CatalogSchedule.matches(
          alias,
          const Anime(id: 1, name: '作品第二季Part.2', year: '2026'),
        ),
        true,
      );
      expect(
        CatalogSchedule.matches(
          alias,
          const Anime(id: 1, name: '作品第二季', year: '2026'),
        ),
        false,
      );
      expect(
        CatalogSchedule.matches(
          alias,
          const Anime(id: 1, name: '作品第二季Part.2', year: '2025'),
        ),
        false,
      );
      var fail = true;
      final service = CatalogSchedule(
        search: (_, {int page = 1}) async {
          if (fail) throw Exception('offline');
          return const CatalogPage([], 0);
        },
        detail: (_) async => throw StateError('unexpected detail'),
      );
      await expectLater(service.resolve(alias), throwsException);
      fail = false;
      expect(await service.resolve(alias), isNull);
    },
  );
  test(
    'continuing title uses premiere year and searches aliases only when clicked',
    () async {
      final queries = <String>[];
      final service = CatalogSchedule(
        search: (q, {int page = 1}) async {
          queries.add(q);
          return CatalogPage(
            q == '海贼王' ? [const Anime(id: 9, name: '海贼王', year: '1999')] : [],
            1,
          );
        },
        detail: (_) async => const Anime(
          id: 9,
          name: '海贼王',
          year: '1999',
          sources: [
            PlaySource('mao', '高速云', ['第01集']),
          ],
        ),
      );
      final anime = await service.resolve(
        ScheduleEntry(
          const Anime(id: -1, name: '航海王', year: '2026'),
          1,
          '',
          premiere: DateTime(1999),
          continuing: true,
        ),
      );
      expect(anime!.id, 9);
      expect(queries, ['海贼王']);
    },
  );
}
