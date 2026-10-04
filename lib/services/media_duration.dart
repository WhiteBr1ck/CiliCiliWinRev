import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class MediaDuration {
  final http.Client client;
  MediaDuration(this.client);
  static int? parsePlaylist(String text) {
    if (!text.trimLeft().startsWith('#EXTM3U') ||
        !text.contains('#EXT-X-ENDLIST')) {
      return null;
    }
    double seconds = 0;
    for (final m in RegExp(
      r'^#EXTINF:([0-9.]+)',
      multiLine: true,
    ).allMatches(text)) {
      final value = double.tryParse(m[1]!);
      if (value == null || !value.isFinite || value <= 0) return null;
      seconds += value;
    }
    return seconds > 0 ? seconds.round() : null;
  }

  Future<int?> load(Playable media) async {
    var url = Uri.tryParse(media.url);
    final visited = <Uri>{};
    for (int depth = 0; depth < 3 && url != null; depth++) {
      if (!['http', 'https'].contains(url.scheme) || !visited.add(url)) {
        return null;
      }
      // Stream with a size bound: never download the video to obtain its duration.
      final response = await client
          .send(http.Request('GET', url)..headers.addAll(media.headers))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 1000000) return null;
        if (bytes.length >= 10 &&
            !utf8
                .decode(bytes.take(32).toList(), allowMalformed: true)
                .replaceFirst('\uFEFF', '')
                .trimLeft()
                .startsWith('#EXTM3U')) {
          return null;
        }
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final duration = parsePlaylist(text);
      if (duration != null) return duration;
      final lines = const LineSplitter().convert(text);
      String? variant;
      for (int i = 0; i < lines.length - 1; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF:')) {
          variant = lines
              .skip(i + 1)
              .map((s) => s.trim())
              .firstWhere(
                (s) => s.isNotEmpty && !s.startsWith('#'),
                orElse: () => '',
              );
          break;
        }
      }
      if (variant == null || variant.isEmpty) return null;
      url = url.resolve(variant);
    }
    return null;
  }
}
