import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class CoverCache {
  static final _loader = CoverLoader(http.Client(), directory);
  static Future<Uint8List?> load(
    String url, {
    String title = '',
    String year = '',
    bool allowFallback = true,
  }) =>
      _loader.load(url, title: title, year: year, allowFallback: allowFallback);

  static Future<Directory> directory() async {
    final root = await getApplicationCacheDirectory();
    return Directory('${root.path}/covers').create(recursive: true);
  }

  // Verified catalog aliases. Keep parts, films and other seasons distinct.
  static String canonical(String value) {
    final name = value.replaceAll(RegExp(r'\s+'), '');
    return switch (name) {
      '死神BLEACH' => '死神',
      '进击的巨人第四季' => '进击的巨人 最终季',
      '进击的巨人第四季Part.2' => '进击的巨人 最终季 Part.2',
      '咒术回战第二季' => '咒术回战 怀玉･玉折 / 涩谷事变',
      '海贼王' => '航海王',
      _ => value,
    };
  }

  static String normalize(String value) => canonical(value)
      .toLowerCase()
      .replaceAll('ⅱ', 'ii')
      .replaceAll(RegExp(r'第[一二三四五六七八九十0-9]+季'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u4e00-\u9fff]'), '');

  static String season(String value) {
    final name = canonical(value);
    if (name.contains('最终季')) return '4';
    final s = RegExp(r'第([一二三四五六七八九十0-9]+)季').firstMatch(name)?[1];
    return const {
          '一': '1',
          '二': '2',
          '三': '3',
          '四': '4',
          '五': '5',
          '六': '6',
          '七': '7',
          '八': '8',
          '九': '9',
          '十': '10',
        }[s] ??
        s ??
        '';
  }

  static String? matchCover(
    String title,
    String year,
    List<dynamic> candidates,
  ) {
    final images = <String>{};
    // This specific CLICLI record has a wrong year (2008 instead of 2004).
    final expectedYear =
        title.replaceAll(RegExp(r'\s+'), '') == '死神BLEACH' && year == '2008'
        ? '2004'
        : year;
    for (final j in candidates.whereType<Map>()) {
      final names = ['${j['name_cn'] ?? ''}', '${j['name'] ?? ''}'];
      if (!names.any(
        (name) =>
            normalize(name) == normalize(title) &&
            season(name) == season(title),
      )) {
        continue;
      }
      final date = '${j['date'] ?? ''}';
      if (RegExp(r'^\d{4}$').hasMatch(expectedYear) &&
          expectedYear != '0000' &&
          (date.length < 4 || date.substring(0, 4) != expectedYear)) {
        continue;
      }
      final image = j['images']?['large'] ?? j['images']?['common'];
      if (image is String && image.isNotEmpty) {
        images.add(image.replaceFirst('http:', 'https:'));
      }
    }
    return images.length == 1 ? images.single : null;
  }
}

/// Shares in-flight work, limits connections and never retains a failed result.
class CoverLoader {
  final http.Client client;
  final Future<Directory> Function() directory;
  final _pending = <String, Future<Uint8List?>>{};
  final _ready = <String, Uint8List>{};
  final _waiting = <Completer<void>>[];
  int _active = 0;
  CoverLoader(this.client, this.directory);
  static const headers = {'User-Agent': 'CiliCiliWinRev/0.6.0 (Windows)'};

  Future<Uint8List?> load(
    String url, {
    String title = '',
    String year = '',
    bool allowFallback = true,
  }) {
    final key = '$url|$title|$year|$allowFallback';
    if (_ready.containsKey(key)) return Future.value(_ready[key]);
    return _pending.putIfAbsent(key, () async {
      try {
        final result = await _limited(
          () => _load(url, title, year, allowFallback),
        );
        if (result != null) {
          if (_ready.length >= 128) _ready.remove(_ready.keys.first);
          _ready[key] = result;
        }
        return result;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<T> _limited<T>(Future<T> Function() work) async {
    if (_active >= 6) {
      final gate = Completer<void>();
      _waiting.add(gate);
      await gate.future;
    } else {
      _active++;
    }
    try {
      return await work();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  static Future<bool> _valid(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final bytes = r.bodyBytes;
          return bytes.isNotEmpty &&
                  bytes.length < 12000000 &&
                  await _valid(bytes)
              ? bytes
              : null;
        }
        if (r.statusCode < 500 && r.statusCode != 429) return null;
      } catch (_) {}
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return null;
  }

  Future<Uint8List?> _load(
    String url,
    String title,
    String year,
    bool fallback,
  ) async {
    File? file;
    try {
      final root = await directory();
      file = File(
        '${root.path}/${md5.convert(utf8.encode('$url|$title|$year'))}',
      );
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (await _valid(bytes)) return bytes;
        await file.delete();
      }
    } catch (_) {}
    var bytes = await _download(url);
    if (bytes == null && fallback && title.isNotEmpty) {
      try {
        final r = await client
            .post(
              Uri.parse('https://api.bgm.tv/v0/search/subjects?limit=15'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'keyword': CoverCache.canonical(title),
                'sort': 'match',
                'filter': {
                  'type': [2],
                },
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          final alt = CoverCache.matchCover(
            title,
            year,
            j['data'] as List? ?? [],
          );
          if (alt != null) bytes = await _download(alt);
        }
      } catch (_) {}
    }
    if (bytes != null && file != null) {
      try {
        await file.writeAsBytes(bytes);
      } catch (_) {}
    }
    return bytes;
  }
}
