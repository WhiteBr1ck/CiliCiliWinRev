import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/media_duration.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'duration uses complete VOD segments, never live or a guessed episode length',
    () {
      expect(
        MediaDuration.parsePlaylist(
          '#EXTM3U\n#EXTINF:12.5,\na.ts\n#EXTINF:10.25,\nb.ts\n#EXT-X-ENDLIST',
        ),
        23,
      );
      expect(
        MediaDuration.parsePlaylist('#EXTM3U\n#EXTINF:12.5,\na.ts'),
        isNull,
      );
      expect(MediaDuration.parsePlaylist('#EXTM3U\n#EXT-X-ENDLIST'), isNull);
    },
  );
  test(
    'master resolves relative playlist with headers and fetches no video segments',
    () async {
      final seen = <String>[];
      final client = MockClient((r) async {
        seen.add(r.url.path);
        expect(r.headers['Referer'], 'https://example.com/');
        return http.Response(
          r.url.path.endsWith('master.m3u8')
              ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\n720/index.m3u8'
              : '#EXTM3U\n#EXTINF:10.1,\n001.ts\n#EXTINF:20.2,\n002.ts\n#EXT-X-ENDLIST',
          200,
        );
      });
      expect(
        await MediaDuration(client).load(
          const Playable('720P', 'https://example.com/master.m3u8', {
            'Referer': 'https://example.com/',
          }),
        ),
        30,
      );
      expect(seen, ['/master.m3u8', '/720/index.m3u8']);
      client.close();
    },
  );
}
