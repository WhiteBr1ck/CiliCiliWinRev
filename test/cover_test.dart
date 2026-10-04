import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clicli_md3/services/cover_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('verified aliases retain season, part and release identity', () {
    final candidates = [
      {
        'name_cn': '进击的巨人 最终季',
        'date': '2020-12-06',
        'images': {'large': 'https://example.com/final.jpg'},
      },
      {
        'name_cn': '进击的巨人 最终季 Part.2',
        'date': '2022-01-09',
        'images': {'large': 'https://example.com/part2.jpg'},
      },
      {
        'name_cn': '咒术回战 怀玉･玉折 / 涩谷事变',
        'date': '2023-07-06',
        'images': {'large': 'https://example.com/jujutsu2.jpg'},
      },
      {
        'name_cn': '死神',
        'name': 'BLEACH',
        'date': '2004-10-05',
        'images': {'large': 'https://example.com/bleach.jpg'},
      },
    ];
    expect(
      CoverCache.matchCover('进击的巨人第四季', '2020', candidates),
      'https://example.com/final.jpg',
    );
    expect(
      CoverCache.matchCover('进击的巨人第四季Part.2', '2022', candidates),
      'https://example.com/part2.jpg',
    );
    expect(
      CoverCache.matchCover('咒术回战 第二季', '2023', candidates),
      'https://example.com/jujutsu2.jpg',
    );
    expect(
      CoverCache.matchCover('死神 BLEACH', '2008', candidates),
      'https://example.com/bleach.jpg',
    );
    expect(CoverCache.matchCover('死神 千年血战篇', '2022', candidates), isNull);
    expect(CoverCache.matchCover('咒术回战 第二季', '2025', candidates), isNull);
    expect(CoverCache.matchCover('进击的巨人第四季', '2022', candidates), isNull);
    expect(
      CoverCache.matchCover('死神 BLEACH', '', [
        {
          'name_cn': '死神',
          'images': {'large': 'https://example.com/a.jpg'},
        },
        {
          'name_cn': '死神',
          'images': {'large': 'https://example.com/b.jpg'},
        },
      ]),
      isNull,
    );
  });
  test(
    'failed and corrupt images can retry, concurrent requests share work',
    () async {
      final root = await Directory.systemTemp.createTemp('clicli-cover-test-');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGMMqDjBwMDAxAAGABJyAZSfZKViAAAAAElFTkSuQmCC',
      );
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        return requests == 1
            ? http.Response('broken', 200)
            : http.Response.bytes(
                png,
                200,
                headers: {'content-type': 'image/png'},
              );
      });
      final loader = CoverLoader(client, () async => root);
      try {
        expect(
          await loader.load('https://example.com/cover', allowFallback: false),
          isNull,
        );
        final result = await Future.wait([
          loader.load('https://example.com/cover', allowFallback: false),
          loader.load('https://example.com/cover', allowFallback: false),
        ]);
        expect(result.every((bytes) => bytes != null), true);
        expect(requests, 2);
        await loader.load('https://example.com/cover', allowFallback: false);
        expect(requests, 2);
      } finally {
        client.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'history with an empty original image still obtains a matched cover',
    () async {
      final root = await Directory.systemTemp.createTemp('clicli-cover-test-');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGMMqDjBwMDAxAAGABJyAZSfZKViAAAAAElFTkSuQmCC',
      );
      final client = MockClient(
        (r) async => r.method == 'POST'
            ? http.Response(
                jsonEncode({
                  'data': [
                    {
                      'name_cn': '进击的巨人 最终季',
                      'date': '2020-12-06',
                      'images': {'large': 'https://example.com/cover'},
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response.bytes(png, 200),
      );
      try {
        expect(
          await CoverLoader(
            client,
            () async => root,
          ).load('', title: '进击的巨人第四季', year: '2020'),
          isNotNull,
        );
      } finally {
        client.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('cover matching never silently picks a different season or film', () {
    final candidates = [
      {
        'name_cn': '无职转生～到了异世界就拿出真本事～',
        'date': '2021-01-10',
        'images': {'large': 'https://example.com/season1.jpg'},
      },
      {
        'name_cn': '无职转生 第三季 ～到了异世界就拿出真本事～',
        'date': '2026-07-04',
        'images': {'large': 'https://example.com/season3.jpg'},
      },
      {
        'name_cn': '无职转生 第三季 ～到了异世界就拿出真本事～ 第2部分',
        'images': {'large': 'https://example.com/part2.jpg'},
      },
    ];
    expect(
      CoverCache.matchCover('无职转生：到了异世界就拿出真本事 第三季', '2026', candidates),
      'https://example.com/season3.jpg',
    );
    expect(
      CoverCache.matchCover('无职转生：到了异世界就拿出真本事 第四季', '', candidates),
      isNull,
    );
    expect(
      CoverCache.matchCover('无职转生：到了异世界就拿出真本事 第三季', '2024', candidates),
      isNull,
    );
    expect(
      CoverCache.matchCover('海贼王', '1999', [
        {
          'name_cn': '海贼王女',
          'date': '2021-10-02',
          'images': {'large': 'https://example.com/wrong.jpg'},
        },
      ]),
      isNull,
    );
  });
}
