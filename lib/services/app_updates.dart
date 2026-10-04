import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app_version.dart';

enum UpdateStatus { idle, checking, current, available, noRelease, failed }

class AppRelease {
  final String version;
  final Uri page, installer;
  final int size;
  const AppRelease(this.version, this.page, this.installer, this.size);
}

/// Uses public GitHub metadata, with a separate client and no account headers.
class AppUpdates extends ChangeNotifier {
  final SharedPreferences preferences;
  final http.Client client;
  final String repository, currentVersion;
  UpdateStatus status = UpdateStatus.idle;
  AppRelease? release;
  String error = '';
  Future<void>? _pending;
  bool _disposed = false;
  AppUpdates(
    this.preferences, {
    http.Client? client,
    this.repository = updateRepository,
    this.currentVersion = appVersion,
  }) : client = client ?? http.Client();

  bool get automatic => preferences.getBool('automaticUpdates') ?? true;
  Future<void> setAutomatic(bool value) async {
    await preferences.setBool('automaticUpdates', value);
    _notify();
  }

  static List<int>? _version(String text) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$').firstMatch(text);
    return m == null ? null : [for (int i = 1; i <= 3; i++) int.parse(m[i]!)];
  }

  static bool isNewer(String candidate, String installed) {
    final a = _version(candidate), b = _version(installed);
    if (a == null || b == null) return false;
    for (int i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  Future<void> check({bool startup = false}) {
    if (_disposed || (startup && !automatic)) return Future.value();
    return _pending ??= _check().whenComplete(() => _pending = null);
  }

  Future<void> _check() async {
    status = UpdateStatus.checking;
    error = '';
    release = null;
    _notify();
    try {
      final response = await client
          .get(
            Uri.https('api.github.com', '/repos/$repository/releases/latest'),
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'CiliCiliWinRev/$currentVersion',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (_disposed) return;
      if (response.statusCode == 404) {
        status = UpdateStatus.noRelease;
        return;
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const FormatException('GitHub 请求受限，请稍后重试');
      }
      if (response.statusCode != 200) {
        throw FormatException('检查失败（HTTP ${response.statusCode}），请重试');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map ||
          data['draft'] == true ||
          data['prerelease'] == true ||
          _version('${data['tag_name']}') == null) {
        throw const FormatException('发行版本信息无效');
      }
      final version = '${data['tag_name']}'.replaceFirst(RegExp(r'^v'), '');
      if (!isNewer(version, currentVersion)) {
        status = UpdateStatus.current;
        return;
      }
      final assets = data['assets'];
      final expectedName = 'CiliCiliWinRev-$version-windows-x64-setup.exe';
      final matches = assets is List
          ? assets
                .whereType<Map>()
                .where((a) => a['name'] == expectedName)
                .toList()
          : <Map>[];
      if (matches.length != 1) {
        throw const FormatException('新版尚未提供 Windows x64 安装包');
      }
      final installer = Uri.tryParse(
        '${matches.single['browser_download_url']}',
      );
      final page = Uri.tryParse('${data['html_url']}');
      final prefix = '/$repository/releases/';
      if (installer == null ||
          page == null ||
          installer.scheme != 'https' ||
          installer.host != 'github.com' ||
          !installer.path.startsWith('${prefix}download/') ||
          page.scheme != 'https' ||
          page.host != 'github.com' ||
          !page.path.startsWith('${prefix}tag/')) {
        throw const FormatException('更新下载地址无效');
      }
      release = AppRelease(
        version,
        page,
        installer,
        matches.single['size'] is int ? matches.single['size'] : 0,
      );
      status = UpdateStatus.available;
    } on TimeoutException {
      if (!_disposed) {
        status = UpdateStatus.failed;
        error = '检查超时，请重试';
      }
    } on FormatException catch (e) {
      if (!_disposed) {
        status = UpdateStatus.failed;
        error = e.message;
      }
    } catch (_) {
      if (!_disposed) {
        status = UpdateStatus.failed;
        error = '无法连接 GitHub，请重试';
      }
    } finally {
      _notify();
    }
  }

  String get label => switch (status) {
    UpdateStatus.idle => '当前版本 $currentVersion',
    UpdateStatus.checking => '正在检查…',
    UpdateStatus.current => '已是最新版本 $currentVersion',
    UpdateStatus.available => '新版本 ${release!.version}',
    UpdateStatus.noRelease => '暂无已发布版本',
    UpdateStatus.failed => error,
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    super.dispose();
  }
}
