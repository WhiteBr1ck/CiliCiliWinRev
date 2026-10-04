import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'measured duration persists by video, source and episode independently of the latest history',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(prefs);
      final first = WatchEntry(
        const Anime(id: 42, name: '作品'),
        'mao',
        '第01集',
        100,
        1400,
        DateTime(2026),
      );
      final second = WatchEntry(
        const Anime(id: 42, name: '作品'),
        'mao',
        '第02集',
        50,
        1500,
        DateTime(2026),
      );
      await state.saveWatch(first);
      await state.saveWatch(second);
      final restored = AppState(prefs);
      expect(restored.knownDuration(first), 1400);
      expect(restored.knownDuration(second), 1500);
      expect(
        restored.knownDuration(
          WatchEntry(first.anime, 'other', '第01集', 100, 0, null),
        ),
        0,
      );
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'favorites, follows, resume position and theme survive reload',
    () async {
      final prefs = await SharedPreferences.getInstance(),
          a = const Anime(id: 42, name: '测试番剧');
      final state = AppState(prefs);
      await state.toggleFavorite(a);
      await state.toggleFavorite(a, follow: true);
      await state.setTheme(ThemeMode.light);
      await state.saveWatch(
        WatchEntry(a, 'mao', '第02集', 123, 1440, DateTime(2026, 10, 4)),
      );
      final restored = AppState(prefs);
      expect(restored.favorites[42]?.name, a.name);
      expect(restored.following.containsKey(42), true);
      expect(restored.history[42]?.position, 123);
      expect(restored.history[42]?.episode, '第02集');
      expect(restored.themeMode, ThemeMode.light);
      await restored.removeWatch(42);
      expect(AppState(prefs).history, isEmpty);
    },
  );
  test('damaged saved data does not prevent the app from starting', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': 'invalid',
      'history': '[{}]',
      'theme': 'unknown',
    });
    final state = AppState(await SharedPreferences.getInstance());
    expect(state.favorites, isEmpty);
    expect(state.history, isEmpty);
    expect(state.themeMode, ThemeMode.dark);
  });
}
