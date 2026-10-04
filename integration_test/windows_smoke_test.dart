import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/services/app_updates.dart';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/main.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:clicli_md3/services/cover_cache.dart';
import 'package:clicli_md3/ui/detail_page.dart';
import 'package:clicli_md3/ui/player_page.dart';
import 'package:clicli_md3/ui/history_page.dart';
import 'package:clicli_md3/ui/account_dialog.dart';
import 'package:clicli_md3/ui/timetable_page.dart';
import 'package:clicli_md3/ui/community_panel.dart';
import 'package:clicli_md3/services/session_store.dart';
import 'package:clicli_md3/services/window_fullscreen.dart';
import 'package:clicli_md3/ui/components.dart';
import 'package:clicli_md3/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Windows catalog, search, H265 playback, seek, next and resume',
    (tester) async {
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      await windowManager.unmaximize();
      await windowManager.setSize(const Size(1360, 900));
      await windowManager.show();
      const store = WindowsSessionStore(fileName: 'integration-account.dpapi');
      try {
        await store.write('integration-fixture');
        expect(await store.read(), 'integration-fixture');
        expect(
          (await (await store.file()).readAsBytes()).length,
          greaterThan(19),
        );
      } finally {
        await store.delete();
      }
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance()),
          api = ClicliApi();
      state.bindAccount(api, storage: SmokeSessionStore());
      await api.loadProtocol();
      final updates = AppUpdates(state.preferences);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ClicliApp(state: state, api: api, updates: updates),
        ),
      );
      Future<void> until(bool Function() condition, {int seconds = 40}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(condition(), true);
      }

      Future<void> resize(Size size) async {
        bool ready() {
          final view = tester.view;
          final logical = view.physicalSize / view.devicePixelRatio;
          return (logical.width - size.width).abs() < 40 &&
              (logical.height - size.height).abs() < 50;
        }

        for (int attempt = 0; attempt < 3; attempt++) {
          await windowManager.restore();
          await windowManager.unmaximize();
          await windowManager.setSize(Size(size.width + 1, size.height + 1));
          await tester.pump(const Duration(milliseconds: 300));
          await windowManager.setSize(size);
          final end = DateTime.now().add(const Duration(seconds: 10));
          while (!ready() && DateTime.now().isBefore(end)) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          if (ready()) break;
        }
        File('.research/resize-geometry.json').writeAsStringSync(
          jsonEncode({
            'native': await WindowFullscreen.geometry(),
            'physicalWidth': tester.view.physicalSize.width,
            'physicalHeight': tester.view.physicalSize.height,
            'dpi': tester.view.devicePixelRatio,
            'targetWidth': size.width,
            'targetHeight': size.height,
          }),
        );
        expect(ready(), true);
        await tester.pump();
      }

      Future<void> screenshot(String name) async {
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('docs/screenshots').createSync(recursive: true);
        File(
          'docs/screenshots/$name.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      }

      await until(() => find.text('开始观看').evaluate().isNotEmpty);
      for (final id in [672, 4513, 9352]) {
        final anime = await api.detail(id);
        expect(
          await CoverCache.load(
            anime.image,
            title: anime.name,
            year: anime.year,
          ),
          isNotNull,
          reason: 'Real missing cover restored: ${anime.name}',
        );
      }
      await tester.pump(const Duration(seconds: 10));
      await screenshot('home-dark');
      await state.setTheme(ThemeMode.light);
      await tester.pump(const Duration(milliseconds: 300));
      await screenshot('home-light');
      await state.setTheme(ThemeMode.dark);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('search')), '无职转生');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await until(
        () =>
            find.text('“无职转生”的搜索结果').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await screenshot('search');
      await tester.tap(find.text('发现').last);
      await tester.pump();
      await tester.tap(find.text('开始观看'));
      await tester.pump();
      await until(() => find.byType(EpisodePicker).evaluate().isNotEmpty);
      await screenshot('detail');
      await tester.tap(find.text('追番'));
      await tester.pump();
      expect(state.following, isNotEmpty);
      await tester.tap(find.byKey(const Key('detail-play')));
      await tester.pump();
      await until(() => find.byType(PlayerPage).evaluate().isNotEmpty);
      final playerState = tester.state<PlayerPageState>(
        find.byType(PlayerPage),
      );
      await until(
        () =>
            playerState.player.state.duration.inSeconds > 0 &&
            playerState.player.state.position.inSeconds >= 2,
        seconds: 60,
      );
      expect(playerState.player.state.width, 1920);
      expect(playerState.player.state.height, 1080);
      await playerState.player.pause();
      await tester.pump();
      await screenshot('player');
      final videoRect = tester.getRect(find.byKey(const Key('video-frame')));
      expect(videoRect.width / videoRect.height, closeTo(16 / 9, .01));
      expect(
        tester.getRect(find.byKey(const Key('danmaku-input'))).top,
        greaterThan(tester.getRect(find.byKey(const Key('seek'))).bottom),
      );
      expect(
        tester.getSize(find.byKey(const Key('danmaku-input'))).width,
        lessThan(400),
      );
      final inputRect = tester.getRect(find.byKey(const Key('danmaku-input')));
      final pauseRect = tester.getRect(find.byKey(const Key('play-pause')));
      expect((inputRect.center.dy - pauseRect.center.dy).abs(), lessThan(15));
      expect(
        inputRect.center.dx,
        closeTo(videoRect.center.dx, videoRect.width * .2),
      );
      expect(
        tester.getSize(find.byKey(const Key('volume-slider'))).width,
        greaterThanOrEqualTo(140),
      );
      final picker = tester.widget<EpisodePicker>(
        find.byType(EpisodePicker).last,
      );
      expect(picker.columns, 3);
      playerState.focus.requestFocus();
      playerState.controlsHovered = false;
      await playerState.player.play();
      playerState.revealControls();
      await tester.pump(const Duration(seconds: 4));
      expect(playerState.controlsVisible, false);
      expect(
        tester
            .widget<MouseRegion>(find.byKey(const Key('video-mouse-region')))
            .cursor,
        SystemMouseCursors.none,
      );
      playerState.revealControls();
      await tester.pump();
      expect(
        tester
            .widget<MouseRegion>(find.byKey(const Key('video-mouse-region')))
            .cursor,
        SystemMouseCursors.basic,
      );
      await playerState.player.pause();
      await tester.pump();
      final controlsRect = tester.getRect(
        find.byKey(const Key('player-controls')),
      );
      expect(videoRect.contains(controlsRect.topLeft), true);
      expect(
        videoRect.contains(controlsRect.bottomRight - const Offset(1, 1)),
        true,
      );
      await state.setTheme(ThemeMode.light);
      await tester.pump();
      await screenshot('player-light');
      await tester.tap(find.text('评论'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(CommunityPanel), findsOneWidget);
      await screenshot('player-comments');
      await until(() => playerState.comments.any((d) => d.time > 0));
      expect(find.byKey(const Key('danmaku-input')), findsOneWidget);
      await resize(const Size(760, 580));
      playerState.revealControls();
      await screenshot('player-narrow');
      final narrowVideo = tester.getRect(find.byKey(const Key('video-frame')));
      expect(narrowVideo.width / narrowVideo.height, closeTo(16 / 9, .01));
      final narrowControls = tester.getRect(
        find.byKey(const Key('player-controls')),
      );
      expect(narrowVideo.contains(narrowControls.topLeft), true);
      expect(
        narrowVideo.contains(narrowControls.bottomRight - const Offset(1, 1)),
        true,
      );
      await tester.enterText(
        find.byKey(const Key('danmaku-input')),
        '测试 f m 空格',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(playerState.fullscreen, false);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('danmaku-input')))
            .controller!
            .text,
        '测试 f m 空格',
      );
      await tester.enterText(find.byKey(const Key('danmaku-input')), '');
      playerState.focus.requestFocus();
      await tester.pump();
      await tester.tap(find.byTooltip('选集与评论'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('评论'));
      await tester.pump(const Duration(seconds: 2));
      await screenshot('player-narrow-comments');
      Navigator.of(tester.element(find.byType(CommunityPanel))).pop();
      await tester.pump(const Duration(milliseconds: 400));
      await resize(const Size(1360, 900));
      playerState.focus.requestFocus();
      await state.setTheme(ThemeMode.dark);
      await tester.pump();
      final duration = playerState.player.state.duration;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await until(() => playerState.fullscreen);
      final full = await WindowFullscreen.geometry();
      expect(full['fullscreen'], true);
      expect(full['width'], full['monitorWidth']);
      expect(full['height'], full['monitorHeight']);
      expect(full['left'], full['monitorLeft']);
      expect(full['top'], full['monitorTop']);
      expect(full['clientWidth'], full['monitorWidth']);
      expect(full['clientHeight'], full['monitorHeight']);
      File(
        '.research/fullscreen-geometry.json',
      ).writeAsStringSync(full.toString());
      await playerState.player.play();
      playerState.revealControls();
      await tester.pump(const Duration(milliseconds: 2200));
      expect(playerState.controlsVisible, false);
      await playerState.player.pause();
      playerState.revealControls();
      await tester.pump();
      await screenshot('player-fullscreen');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await until(() => !playerState.fullscreen);
      expect((await WindowFullscreen.geometry())['fullscreen'], false);
      await windowManager.maximize();
      await tester.pump(const Duration(milliseconds: 400));
      await playerState.toggleFullscreen();
      await tester.pump(const Duration(milliseconds: 400));
      final maxFull = await WindowFullscreen.geometry();
      expect(maxFull['width'], maxFull['monitorWidth']);
      expect(maxFull['height'], maxFull['monitorHeight']);
      await playerState.toggleFullscreen();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await windowManager.isMaximized(), true);
      await windowManager.unmaximize();
      await resize(const Size(1360, 900));
      expect(find.byType(PlayerPage), findsOneWidget);
      await playerState.player.seek(const Duration(seconds: 25));
      await until(() => playerState.player.state.position.inSeconds >= 24);
      await playerState.save();
      expect(state.recent.first.position, greaterThanOrEqualTo(24));
      final initial = playerState.episode;
      if (playerState.hasNext) {
        await playerState.switchEpisode(
          playerState.source.episodes[playerState.nextIndex],
        );
        await until(
          () =>
              playerState.player.state.duration.inSeconds > 0 &&
              playerState.player.state.position.inSeconds >= 1,
          seconds: 60,
        );
        expect(playerState.episode, isNot(initial));
        expect(playerState.player.state.duration, greaterThan(Duration.zero));
        await playerState.player.pause();
        await playerState.player.seek(const Duration(seconds: 25));
        await until(() => playerState.player.state.position.inSeconds >= 24);
        await playerState.save();
      }
      final saved = state.recent.first;
      final measured = await api.episodeDuration(saved);
      expect(measured, isNotNull);
      expect(measured!, closeTo(saved.duration, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await until(
        () => find.byType(PlayerPage, skipOffstage: false).evaluate().isEmpty,
      );
      expect(find.byType(DetailPage), findsOneWidget);
      expect(state.recent, isNotEmpty);
      expect(duration, greaterThan(Duration.zero));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await until(
        () => find.byType(DetailPage, skipOffstage: false).evaluate().isEmpty,
      );
      await tester.tap(find.text('新番时间表'));
      await tester.pump();
      await until(
        () =>
            find.byType(TimetablePage).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        seconds: 90,
      );
      await screenshot('timetable');
      expect(find.byType(ErrorView), findsNothing);
      final seasonal = await api.timetable(
        DateTime.now().year,
        quarter: (DateTime.now().month - 1) ~/ 3 + 1,
      );
      expect(seasonal.items, isNotEmpty);
      expect(seasonal.items.length, greaterThan(20));
      expect(seasonal.items.every((e) => e.anime.id < 0), true);
      final publicQuarter = await api.seasonSchedule.load(
        DateTime.now().year,
        (DateTime.now().month - 1) ~/ 3 + 1,
      );
      File('.research/catalog-public-quarter.json').writeAsStringSync(
        jsonEncode([
          for (final item in publicQuarter)
            {
              'name': item.anime.name,
              'original': item.originalName,
              'aliases': item.aliases,
              'year': item.premiere?.year,
              'time': item.time,
            },
        ]),
      );
      for (final entry in seasonal.items) {
        final original = publicQuarter.singleWhere(
          (e) => e.subjectId == entry.subjectId,
        );
        expect(entry.time, original.time);
        expect(entry.airingAt, original.airingAt);
      }
      final grid = tester.widget<GridView>(
        find.descendant(
          of: find.byType(TimetablePage),
          matching: find.byType(GridView),
        ),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      File('.research/season-summary.txt').writeAsStringSync(
        'Total: ${seasonal.items.length}\nTV/WEB: ${seasonal.items.where((e) => ['TV', 'WEB', ''].contains(e.platform)).length}\nUnknown weekdays: ${seasonal.items.where((e) => e.weekday == 0).length}\nBroadcast times: ${seasonal.items.where((e) => e.airingAt != null).length}',
      );
      expect(find.text('加载更多'), findsNothing);
      final firstScheduled = seasonal.items.firstWhere(
        (e) => e.anime.name == '航海王',
      );
      await tester.scrollUntilVisible(
        find.text(firstScheduled.anime.name),
        400,
        scrollable: find
            .descendant(
              of: find.byType(TimetablePage),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text(firstScheduled.anime.name).first);
      await tester.pump();
      await until(
        () =>
            find.byType(DetailPage).evaluate().isNotEmpty &&
            find.byType(EpisodePicker).evaluate().isNotEmpty,
      );
      expect(find.byType(DetailPage), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await until(
        () => find.byType(DetailPage, skipOffstage: false).evaluate().isEmpty,
      );
      await tester.tap(find.text('设置'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('accent-teal')));
      await tester.pump();
      expect(state.accent, 'teal');
      expect(
        Theme.of(
          tester.element(find.byKey(const Key('accent-teal'))),
        ).colorScheme.primary,
        AppTheme.make(Brightness.dark, accent: 'teal').colorScheme.primary,
      );
      await screenshot('settings-accent');
      await tester.scrollUntilVisible(
        find.text('检查更新'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await updates.check();
      expect(
        updates.status,
        anyOf(UpdateStatus.noRelease, UpdateStatus.current),
      );
      await screenshot('settings-updates');
      await state.setAccent('purple');
      await tester.pump();
      await tester.tap(find.text('登录 / 注册'));
      await tester.pump();
      await screenshot('login');
      expect(find.byType(AccountDialog), findsOneWidget);
      await tester.tap(find.text('注册账号'));
      await tester.pump();
      await screenshot('register');
      await tester.tap(find.byTooltip('关闭').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DetailPage), findsNothing);
      await tester.tap(find.text('观看历史').first);
      await tester.pump();
      await screenshot('history');
      expect(find.byTooltip('继续观看'), findsOneWidget);
      await tester.tap(find.byTooltip('继续观看'));
      await tester.pump();
      await until(() => find.byType(EpisodePicker).evaluate().isNotEmpty);
      await tester.tap(find.byKey(const Key('detail-play')));
      await tester.pump();
      await until(() => find.byType(PlayerPage).evaluate().isNotEmpty);
      final resumed = tester.state<PlayerPageState>(find.byType(PlayerPage));
      await until(
        () => resumed.player.state.position.inSeconds >= saved.position - 2,
        seconds: 60,
      );
      expect(resumed.episode, saved.episode);
      expect(resumed.source.id, saved.source);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await until(
        () => find.byType(PlayerPage, skipOffstage: false).evaluate().isEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await until(
        () => find.byType(DetailPage, skipOffstage: false).evaluate().isEmpty,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('search')))
            .focusNode!
            .hasFocus,
        true,
      );
      expect(tester.takeException(), isNull);
      final restoredCovers = <Anime>[];
      for (final id in [672, 4513, 9352]) {
        restoredCovers.add(await api.detail(id));
      }
      // Reuse the actual card component and actual catalog records for evidence.
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.make(Brightness.light),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 900,
                  height: 470,
                  child: Row(
                    children: [
                      for (final anime in restoredCovers)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: AnimeCard(anime: anime, onTap: () {}),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await screenshot('covers-restored');
      final historyApi = SmokeHistoryApi()..token = 'fixture';
      final historyState = AppState(await SharedPreferences.getInstance());
      historyState.bindAccount(historyApi, storage: SmokeSessionStore());
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.make(Brightness.light),
            home: Scaffold(
              body: HistoryPage(
                state: historyState,
                api: historyApi,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('账号'));
      await tester.pump(const Duration(seconds: 3));
      await screenshot('history-account');
      expect(find.text('观看于 10:30'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('history-progress-672')),
            )
            .value,
        closeTo(600 / 1440, .001),
      );
      expect(find.textContaining('2026-10-04'), findsOneWidget);
      expect(find.text('时间未知'), findsOneWidget);
      expect(tester.takeException(), isNull);
      historyApi.dispose();
      updates.dispose();
      api.dispose();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

class SmokeSessionStore implements SessionStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> delete() async {
    token = null;
  }
}

class SmokeHistoryApi extends ClicliApi {
  @override
  Future<int?> episodeDuration(WatchEntry entry) async => 1440;
  @override
  Future<RecordPage<AccountHistory>> accountHistory({int page = 1}) async =>
      RecordPage([
        AccountHistory(
          672,
          WatchEntry(
            const Anime(id: 672, name: '死神 BLEACH', year: '2008'),
            'mao',
            '第01集',
            600,
            0,
            DateTime(2026, 10, 4, 10, 30),
          ),
        ),
        AccountHistory(
          4513,
          WatchEntry(
            const Anime(id: 4513, name: '进击的巨人第四季', year: '2020'),
            'mao',
            '第01集',
            730,
            0,
            DateTime(2026, 10, 3, 21, 15),
          ),
        ),
        const AccountHistory(
          9352,
          WatchEntry(
            Anime(id: 9352, name: '咒术回战 第二季', year: '2023'),
            'mao',
            '第02集',
            360,
            0,
            null,
          ),
        ),
      ], 3);
}
