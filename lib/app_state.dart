import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/account_session.dart';
import 'services/clicli_api.dart';
import 'services/session_store.dart';
import 'theme.dart';

class AppState extends ChangeNotifier {
  Future<void> Function()? flushPlayback;
  AccountSession? account;
  void bindAccount(ClicliApi api, {SessionStore? storage}) {
    if (account != null) return;
    account = AccountSession(
      api,
      storage: storage ?? const WindowsSessionStore(),
    )..addListener(notifyListeners);
  }

  final SharedPreferences preferences;
  ThemeMode themeMode = ThemeMode.dark;
  bool autoNext = true, showDanmaku = true;
  double volume = 80;
  String accent = 'purple';
  double danmakuOpacity = .8, danmakuFontSize = 18, danmakuArea = .5;
  final Map<int, Anime> favorites = {}, following = {};
  final Map<int, WatchEntry> history = {};
  final Map<String, int> _durations = {};
  static String durationKey(WatchEntry entry) =>
      '${entry.anime.id}|${entry.source}|${entry.episode}';
  int knownDuration(WatchEntry entry) => _durations[durationKey(entry)] ?? 0;
  Future<void> rememberDuration(WatchEntry entry, int duration) async {
    if (duration <= 0) return;
    final key = durationKey(entry);
    if (_durations[key] == duration) return;
    _durations.remove(key);
    _durations[key] = duration;
    while (_durations.length > 300) {
      _durations.remove(_durations.keys.first);
    }
    await preferences.setString('episodeDurations', jsonEncode(_durations));
  }

  AppState(this.preferences) {
    try {
      final durations =
          jsonDecode(preferences.getString('episodeDurations') ?? '{}') as Map;
      for (final e in durations.entries) {
        final value = number(e.value);
        if (value > 0) _durations['${e.key}'] = value;
      }
    } catch (_) {}
    final mode = preferences.getString('theme');
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => ThemeMode.dark,
    );
    autoNext = preferences.getBool('autoNext') ?? true;
    showDanmaku = preferences.getBool('danmaku') ?? true;
    volume = preferences.getDouble('volume') ?? 80;
    final savedAccent = preferences.getString('accent');
    if (AppTheme.accents.containsKey(savedAccent)) accent = savedAccent!;
    danmakuOpacity = (preferences.getDouble('danmakuOpacity') ?? .8).clamp(
      .2,
      1,
    );
    danmakuFontSize = (preferences.getDouble('danmakuFontSize') ?? 18).clamp(
      14,
      30,
    );
    danmakuArea = (preferences.getDouble('danmakuArea') ?? .5).clamp(.25, 1);
    _loadAnime('favorites', favorites);
    _loadAnime('following', following);
    for (final j in _loadList('history')) {
      try {
        final e = WatchEntry.fromJson(j);
        history[e.anime.id] = e;
        if (e.duration > 0) _durations[durationKey(e)] = e.duration;
      } catch (_) {}
    }
  }
  List<Map<String, dynamic>> _loadList(String key) {
    try {
      return (jsonDecode(preferences.getString(key) ?? '[]') as List)
          .map((j) => Map<String, dynamic>.from(j))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _loadAnime(String key, Map<int, Anime> target) {
    for (final j in _loadList(key)) {
      try {
        final a = Anime.fromJson(j);
        target[a.id] = a;
      } catch (_) {}
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await preferences.setString('theme', mode.name);
  }

  Future<void> setAutoNext(bool value) async {
    autoNext = value;
    notifyListeners();
    await preferences.setBool('autoNext', value);
  }

  Future<void> setAccent(String value) async {
    if (!AppTheme.accents.containsKey(value)) return;
    accent = value;
    notifyListeners();
    await preferences.setString('accent', value);
  }

  Future<void> setDanmakuStyle({
    double? opacity,
    double? fontSize,
    double? area,
  }) async {
    danmakuOpacity = (opacity ?? danmakuOpacity).clamp(.2, 1);
    danmakuFontSize = (fontSize ?? danmakuFontSize).clamp(14, 30);
    danmakuArea = (area ?? danmakuArea).clamp(.25, 1);
    notifyListeners();
    await preferences.setDouble('danmakuOpacity', danmakuOpacity);
    await preferences.setDouble('danmakuFontSize', danmakuFontSize);
    await preferences.setDouble('danmakuArea', danmakuArea);
  }

  Future<void> setDanmaku(bool value) async {
    showDanmaku = value;
    notifyListeners();
    await preferences.setBool('danmaku', value);
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 100);
    await preferences.setDouble('volume', volume);
  }

  Future<void> toggleFavorite(Anime a, {bool follow = false}) async {
    final map = follow ? following : favorites;
    map.containsKey(a.id) ? map.remove(a.id) : map[a.id] = a;
    notifyListeners();
    await preferences.setString(
      follow ? 'following' : 'favorites',
      jsonEncode(map.values.map((a) => a.toJson()).toList()),
    );
  }

  List<WatchEntry> get recent => history.values.toList()
    ..sort(
      (a, b) =>
          (b.updated ?? DateTime(1970)).compareTo(a.updated ?? DateTime(1970)),
    );
  Future<void> saveWatch(WatchEntry entry, {bool notify = true}) async {
    await rememberDuration(entry, entry.duration);
    history[entry.anime.id] = entry;
    final entries = recent.take(150).toList();
    history
      ..clear()
      ..addEntries(entries.map((e) => MapEntry(e.anime.id, e)));
    if (notify) notifyListeners();
    await preferences.setString(
      'history',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> removeWatch(int id) async {
    history.remove(id);
    notifyListeners();
    await preferences.setString(
      'history',
      jsonEncode(recent.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    history.clear();
    notifyListeners();
    await preferences.remove('history');
  }
}
