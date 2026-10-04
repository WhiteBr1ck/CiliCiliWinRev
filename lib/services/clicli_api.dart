import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/asymmetric/api.dart';
import '../models.dart';
import 'season_schedule.dart';
import 'catalog_schedule.dart';
import 'media_duration.dart';

class ApiException implements Exception {
  final String message;
  final int? code;
  final Map<String, dynamic>? data;
  const ApiException(this.message, {this.code, this.data});
  @override
  String toString() => message;
}

/// Compatibility with the wire protocol shipped in CLICLI Windows 1.1.5.
/// Catalog, playback and account protocol. It sends no telemetry.
class ClicliApi {
  final http.Client client;
  late Map<String, dynamic> _protocol;
  late enc.Encrypter _rsa;
  late enc.Encrypter _sendRsa;
  String? host;
  String? token;
  Set<int> vipChannels = {};
  void Function()? onSessionExpired;
  late final SeasonSchedule seasonSchedule = SeasonSchedule(client);
  late final CatalogSchedule catalogSchedule = CatalogSchedule(
    search: (keyword, {int page = 1}) =>
        _catalogRead(() => search(keyword, page: page)),
    detail: (id) => _catalogRead(() => detail(id)),
  );
  Future<void> _catalogReadQueue = Future<void>.value();

  Future<T> _catalogRead<T>(Future<T> Function() read) {
    final result = _catalogReadQueue.then((_) async {
      for (int attempt = 0; ; attempt++) {
        // Serialize background reads; a cooldown also pauses every queued worker.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        try {
          return await read();
        } on ApiException catch (e) {
          if (attempt >= 2 ||
              !(e.code == 429209 || e.message.contains('HTTP 429'))) {
            rethrow;
          }
          await Future<void>.delayed(Duration(seconds: 15 * (attempt + 1)));
        }
      }
    });
    _catalogReadQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  ClicliApi({http.Client? client}) : client = client ?? http.Client();

  final _authAes = enc.Encrypter(
    enc.AES(
      enc.Key.fromUtf8('ziISjqkXPsGUMRNGyWigxDGtJbfTdcGv'),
      mode: enc.AESMode.cbc,
    ),
  );
  final _authIv = enc.IV.fromUtf8('WonrnVkxeIxDcFbv');

  Future<void> loadProtocol() async {
    _protocol = jsonDecode(
      (await rootBundle.loadString(
        'assets/protocol.json',
      )).replaceFirst('\uFEFF', ''),
    );
    final pem = utf8.decode(base64.decode(_protocol['receive']));
    _rsa = enc.Encrypter(
      enc.RSA(privateKey: enc.RSAKeyParser().parse(pem) as RSAPrivateKey),
    );
    _sendRsa = enc.Encrypter(
      enc.RSA(
        publicKey:
            enc.RSAKeyParser().parse(
                  utf8.decode(base64.decode(_protocol['send'])),
                )
                as RSAPublicKey,
      ),
    );
  }

  String encodeBody(Map<String, dynamic> data) {
    const key = 'R5xThLNmXbpDOgyj';
    final aes = enc.Encrypter(
      enc.AES(enc.Key.fromUtf8(key), mode: enc.AESMode.cbc),
    );
    return '${_sendRsa.encrypt(key).base64}.${aes.encrypt(jsonEncode(data), iv: enc.IV.fromUtf8(key.split('').reversed.join())).base64}';
  }

  Map<String, String> headers({DateTime? now}) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final value = base64.encode(utf8.encode('1.1.5-$ts-3-1.0.0-win32'));
    return {
      'Content-Type': 'application/json',
      'ts': '$ts',
      'system': '3',
      'APPID': '${_protocol['appId']}',
      'X-VERSION': '${_protocol['version']}',
      'Authentication': _authAes.encrypt(value, iv: _authIv).base64,
      if (token != null && token!.isNotEmpty) 'X-Token': token!,
    };
  }

  Map<String, dynamic> decodeResponse(String body) {
    final text = body.trim();
    if (text.startsWith('{')) {
      return Map<String, dynamic>.from(jsonDecode(text));
    }
    final parts = text.split('.');
    if (parts.length != 2) throw const ApiException('服务器返回了无法识别的数据，请重试。');
    final key = _rsa.decrypt64(parts[0]);
    final aes = enc.Encrypter(
      enc.AES(enc.Key.fromUtf8(key), mode: enc.AESMode.cbc),
    );
    return Map<String, dynamic>.from(
      jsonDecode(
        aes.decrypt64(
          parts[1],
          iv: enc.IV.fromUtf8(key.split('').reversed.join()),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, String>? query,
    String? base,
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final server = base ?? host;
    if (server == null) throw const ApiException('尚未连接到片库，请在设置中重新连接。');
    final uri = Uri.parse('$server$path').replace(queryParameters: query);
    try {
      final message = http.Request(method, uri)..headers.addAll(headers());
      final sentToken = token;
      if (body != null && body.isNotEmpty) message.body = encodeBody(body);
      final response = await http.Response.fromStream(
        await client.send(message).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw ApiException('连接失败（HTTP ${response.statusCode}），请稍后重试。');
      }
      final result = decodeResponse(utf8.decode(response.bodyBytes));
      if (result['code'] != 20000) {
        final code = number(result['code']);
        if ([50014, 50008, 500403].contains(code) &&
            token != null &&
            token == sentToken) {
          token = null;
          vipChannels.clear();
          onSessionExpired?.call();
        }
        throw ApiException(
          cleanText(result['message'] ?? result['msg'] ?? '请求失败，请稍后重试。'),
          code: code,
          data: result['data'] is Map
              ? Map<String, dynamic>.from(result['data'])
              : null,
        );
      }
      return result;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException('无法连接服务器，请检查网络后重试。');
    } on FormatException {
      throw const ApiException('片库数据格式已变化，请更新客户端。');
    } catch (_) {
      throw const ApiException('请求超时或数据解密失败，请检查网络后重试。');
    }
  }

  Future<String> connect({String? cachedHost}) async {
    if (cachedHost != null &&
        ['http', 'https'].contains(Uri.tryParse(cachedHost)?.scheme)) {
      try {
        await request(
          '/pc/channel',
          query: {'top-level': 'true'},
          base: cachedHost,
        );
        host = cachedHost;
        return host!;
      } catch (_) {}
    }
    final prefix = md5
        .convert(utf8.encode(_protocol['appId']))
        .toString()
        .substring(24);
    for (final domain in ['vps.jp', 'jpy.jp', 'whalece.org', 'judian.jp']) {
      try {
        final addresses = await InternetAddress.lookup(
          '${prefix}3.staticcard.$domain',
        ).timeout(const Duration(seconds: 4));
        for (final address in addresses.where(
          (a) => a.type == InternetAddressType.IPv4,
        )) {
          final data = await request(
            '/app/config/host',
            base: 'http://${address.address}:7862',
          );
          final decoded = _authAes.decrypt64(data['data'], iv: _authIv);
          final config = jsonDecode(utf8.decode(base64.decode(decoded)));
          final candidate = '${config['host']}'.replaceFirst(RegExp(r'/$'), '');
          final uri = Uri.tryParse(candidate);
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty) {
            continue;
          }
          host = candidate;
          return candidate;
        }
      } catch (_) {}
    }
    throw const ApiException('片库暂时无法连接。请检查网络，或稍后点“重新连接”。');
  }

  Future<List<Channel>> channels() async =>
      ((await request('/pc/channel', query: {'top-level': 'true'}))['data']
              as List)
          .map((j) => Channel.fromJson(Map<String, dynamic>.from(j)))
          .toList();
  Future<List<Anime>> banners([int channel = 0]) async =>
      ((await request('/pc/banners/$channel'))['data'] as List)
          .map((j) => Anime.fromJson(Map<String, dynamic>.from(j)))
          .toList();
  Future<CatalogPage> list({
    int channel = 0,
    int page = 1,
    String sort = 'hits',
    String? year,
    String? genre,
    String? area,
  }) async {
    final j = (await request(
      '/pc/video/list',
      query: {
        'channel': '$channel',
        'page': '$page',
        'limit': '24',
        'sort': sort,
        if (year != null) 'year': year,
        if (genre != null) 'type': genre,
        if (area != null) 'area': area,
      },
    ))['data'];
    return CatalogPage(
      (j['items'] as List? ?? [])
          .map((x) => Anime.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
      number(j['total']),
    );
  }

  Future<CatalogPage> search(String keyword, {int page = 1}) async {
    final j = (await request(
      '/pc/video/search',
      query: {'key': keyword, 'page': '$page', 'limit': '24'},
    ))['data'];
    return CatalogPage(
      (j['items'] as List? ?? [])
          .map((x) => Anime.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
      number(j['total']),
    );
  }

  Future<Anime> detail(int id) async => Anime.fromJson(
    Map<String, dynamic>.from(
      (await request('/pc/video/detail', query: {'id': '$id'}))['data'],
    ),
  );

  Future<Map<String, dynamic>> login(String account, String password) async {
    final email = account.contains('@');
    return Map<String, dynamic>.from(
      (await request(
        '/pc/users/login',
        method: 'POST',
        body: {
          'enum': email ? 1 : 0,
          'email': email ? account : '',
          'phone': email ? '' : account,
          'password': password,
          'symbol': 'win32',
        },
      ))['data'],
    );
  }

  Future<Map<String, dynamic>> loginWithCode(String email, String code) async =>
      Map<String, dynamic>.from(
        (await request(
          '/pc/users/loginWithCode',
          method: 'POST',
          body: {'email': email, 'code': code},
        ))['data'],
      );
  Future<Map<String, dynamic>> userInfo() async {
    final requestedToken = token;
    final data = Map<String, dynamic>.from(
      (await request('/pc/users/info'))['data'],
    );
    if (requestedToken == token) {
      vipChannels = (data['vips'] as List? ?? [])
          .whereType<Map>()
          .map((v) => number(v['vip_channel']))
          .toSet();
    }
    return data;
  }

  Future<void> logout() async {
    await request('/pc/users/logout', method: 'POST');
  }

  Future<RecordPage<Anime>> accountFavorites({int page = 1}) async {
    final data = (await request(
      '/pc/collect',
      query: {'page': '$page', 'limit': '24'},
    ))['data'];
    return RecordPage(
      (data['items'] as List? ?? [])
          .map((j) => Anime.fromJson(Map<String, dynamic>.from(j)))
          .toList(),
      number(data['total']),
    );
  }

  Future<void> setAccountFavorite(int id, {required bool collected}) async {
    await request(
      '/pc/collect',
      method: collected ? 'POST' : 'DELETE',
      body: {'vid': id},
    );
  }

  Future<void> register({
    required String nickname,
    required String email,
    required String password,
    required String code,
  }) async {
    await request(
      '/pc/users/register',
      method: 'POST',
      body: {
        'user_name': nickname,
        'email': email,
        'password': password,
        'smscode': code,
        'enum': 1,
        'phone': '',
      },
    );
  }

  Future<void> sendCode(
    String email,
    String type, {
    String uuid = '',
    String dots = '',
  }) async {
    await request(
      '/pc/users/smscode',
      method: 'POST',
      body: {
        'email': email,
        'type': type,
        'enum': 1,
        'uuid': uuid,
        'dots': dots,
      },
    );
  }

  Future<Map<String, dynamic>> captcha(String type) async =>
      Map<String, dynamic>.from(
        (await request(
          '/pc/users/captcha',
          method: 'POST',
          body: {'type': type},
        ))['data'],
      );
  Future<Map<String, dynamic>> agreement() async =>
      Map<String, dynamic>.from((await request('/app/agreement'))['data']);
  Future<RecordPage<AccountHistory>> accountHistory({int page = 1}) async {
    final data = (await request(
      '/pc/history',
      query: {'page': '$page', 'limit': '24'},
    ))['data'];
    return RecordPage(
      (data['items'] as List? ?? [])
          .map((j) => AccountHistory.fromJson(Map<String, dynamic>.from(j)))
          .toList(),
      number(data['total']),
    );
  }

  Future<void> saveAccountHistory(WatchEntry entry) async {
    await request(
      '/pc/history',
      method: 'POST',
      body: {
        'type': 'post',
        'vid': entry.anime.id,
        'play': entry.source,
        'part': entry.episode,
        'time_point': entry.position,
      },
    );
  }

  Future<void> deleteAccountHistory(int id) async {
    await request(
      '/pc/history',
      method: 'DELETE',
      body: {
        'ids': [id],
      },
    );
  }

  Future<RecordPage<VodComment>> vodComments(int id, {int page = 1}) async {
    final data = (await request(
      '/pc/vod_comment/getlist',
      query: {'vid': '$id', 'page': '$page', 'limit': '20'},
    ))['data'];
    return RecordPage(
      (data['items'] as List? ?? [])
          .map((j) => VodComment.fromJson(Map<String, dynamic>.from(j)))
          .toList(),
      number(data['total']),
    );
  }

  Future<RecordPage<VodComment>> replies(int id, {String marker = ''}) async {
    final data = (await request(
      '/pc/vod_comment/getsublist',
      query: {'theme_cid': '$id', 'marker': marker, 'limit': '20'},
    ))['data'];
    return RecordPage(
      (data['items'] as List? ?? [])
          .map((j) => VodComment.fromJson(Map<String, dynamic>.from(j)))
          .toList(),
      number(data['total']),
    );
  }

  Future<void> postComment(
    int id,
    String text, {
    int lastId = 0,
    String uuid = '',
    String dots = '',
  }) async {
    await request(
      '/pc/vod_comment/create',
      method: 'POST',
      body: {
        'vid': id,
        'comments': text,
        'last_id': lastId,
        'uuid': uuid,
        'dots': dots,
      },
    );
  }

  Future<Map<String, dynamic>> commentCaptcha() async =>
      Map<String, dynamic>.from(
        (await request('/pc/vod_comment/captcha'))['data'],
      );

  Future<void> likeComment(int vid, VodComment comment) async {
    await request(
      '/pc/vod_comment/likes',
      method: 'POST',
      body: {'vid': vid, 'id': comment.id, 'like': !comment.liked},
    );
  }

  Future<TimetableBatch> timetable(
    int year, {
    int quarter = 1,
    int batch = 1,
  }) async => TimetableBatch(await seasonSchedule.load(year, quarter));

  void invalidateTimetable(int year, int quarter) =>
      seasonSchedule.invalidate(year, quarter);

  Future<Anime?> scheduledAnime(ScheduleEntry entry) =>
      catalogSchedule.resolve(entry);

  Future<int?> episodeDuration(WatchEntry entry) async {
    final choices = await _catalogRead(
      () => resolve(
        entry.anime.id,
        entry.source,
        entry.episode,
        channel: entry.anime.channel,
      ),
    );
    return choices.isEmpty ? null : MediaDuration(client).load(choices.first);
  }

  Future<List<Playable>> resolve(
    int id,
    String source,
    String episode, {
    int channel = 0,
  }) async {
    final response = await request(
      '/pc/video/play',
      query: {'id': '$id', 'play': source, 'part': episode},
    );
    final entries = (response['data'] as List).cast<Map<String, dynamic>>();
    final free = entries
        .where(
          (x) =>
              (number(x['vip_type']) == 0 ||
                  (token != null &&
                      (vipChannels.contains(channel) ||
                          vipChannels.contains(-1)))) &&
              '${x['url'] ?? ''}'.isNotEmpty,
        )
        .toList()
        .reversed
        .toList();
    if (free.isEmpty) throw const ApiException('这个播放源需要原站账号权限，请选择其他播放源。');
    final first = free.first;
    final script = '${first['parse'] ?? ''}';
    // Parse the known provider template as data. Never execute server-supplied Lua.
    if (number(first['ps']) == 1 && script.contains('playaddr/lua/v4/get')) {
      String capture(String pattern) =>
          RegExp(pattern).firstMatch(script)?.group(1) ?? '';
      final endpoint = capture(r'local uri\s*=\s*"([^"]+)');
      final appId = capture(r'local appId\s*=\s*"([^"]+)');
      final appKey = capture(r'local appKey\s*=\s*"([^"]+)');
      final code = '${first['url']}';
      if (endpoint.isEmpty || appId.isEmpty || appKey.isEmpty) {
        throw const ApiException('播放解析规则已变化，请选择其他播放源。');
      }
      final uri = Uri.parse(
        '$endpoint${Uri.encodeComponent(code)}&definition=ALL&clientIp=null&second=0',
      );
      final res = await client
          .get(
            uri,
            headers: {
              'appId': appId,
              'Authentication': md5
                  .convert(utf8.encode('$code-ALL-null-0-$appKey'))
                  .toString(),
            },
          )
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j['code'] != 0) {
        throw ApiException(cleanText(j['msg'] ?? '播放源暂时不可用，请重试。'));
      }
      return _providerAddresses(j);
    }
    if (source == 'mao' && !script.contains('function parser')) {
      final random = Random.secure();
      final nonce = List.generate(
        16,
        (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
      ).join();
      final auth = (await request(
        '/pc/video/authenticatePlayVideo',
        query: {
          'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
          'nonce': nonce,
          'vcode': '${first['url']}',
          'vid': '$id',
          'resolution': '${first['resolution']}',
          'play': source,
          'part': episode,
        },
      ))['data'];
      final res = await client
          .post(
            Uri.parse('https://vod.api.zshtys888.com/app/playaddr/v4/client'),
            headers: {
              'Content-Type': 'application/json',
              'Timestamp': '${auth['timestamp']}',
              'Nonce': '${auth['nonce']}',
              'Authorization': '${auth['authorization']}',
              'SecretId': '${auth['secretid']}',
            },
            body: jsonEncode({'ciphertext': auth['ciphertext']}),
          )
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j['code'] != 0) {
        throw ApiException(cleanText(j['msg'] ?? '播放鉴权失败，请重试。'));
      }
      return _providerAddresses(j);
    }
    if (number(first['ps']) == 1) {
      throw const ApiException('暂不支持这个播放源的解析规则，请选择其他源。');
    }
    final result = free
        .where(
          (x) =>
              ['http', 'https'].contains(Uri.tryParse('${x['url']}')?.scheme),
        )
        .map(
          (x) => Playable(
            '${x['resolution'] ?? '自动'}',
            '${x['url']}',
            (x['lua_header'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')),
          ),
        )
        .toList();
    if (result.isEmpty) throw const ApiException('播放源未返回可用地址，请选择其他源。');
    return result;
  }

  List<Playable> _providerAddresses(dynamic j) {
    final items = (j['data']?['playAddr'] as List? ?? []);
    final result = items
        .map(
          (x) => Playable(
            '${x['desc'] ?? x['title'] ?? '自动'}',
            '${x['m3u8FileDomain'] ?? ''}${x['addr'] ?? ''}',
          ),
        )
        .where((x) => ['http', 'https'].contains(Uri.tryParse(x.url)?.scheme))
        .toList();
    if (result.isEmpty) throw const ApiException('播放源没有返回视频地址，请重试。');
    return result;
  }

  Future<List<Map<String, dynamic>>> danmaku(
    int id,
    String source,
    String episode,
    int start, {
    int? end,
  }) async {
    final j = (await request(
      '/pc/danmu',
      query: {
        'vid': '$id',
        'play': source,
        'part': episode,
        'start_time_point': '$start',
        'end_time_point': '${end ?? start + 60}',
      },
    ))['data'];
    return (j['items'] as List? ?? [])
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
  }

  Future<void> sendDanmaku(
    int id,
    String source,
    String episode,
    double time,
    String text, {
    int color = 0xFFFFFFFF,
    int type = 0,
    String size = 'M',
    String uuid = '',
    String dots = '',
  }) async {
    if (!time.isFinite || time < 0 || text.trim().isEmpty) {
      throw const ApiException('弹幕内容或时间无效');
    }
    await request(
      '/pc/danmu',
      method: 'POST',
      body: {
        'type': 'put',
        'vid': id,
        'play': source,
        'part': episode,
        'time_point': time.floor(),
        'content': jsonEncode({
          'content': text.trim(),
          'color': color,
          'type': type,
          'size': size,
        }),
        'uuid': uuid,
        'dots': dots,
      },
    );
  }

  Future<Map<String, dynamic>> danmakuCaptcha() async =>
      Map<String, dynamic>.from((await request('/pc/danmu/captcha'))['data']);

  void dispose() => client.close();
}
