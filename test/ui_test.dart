import 'dart:convert';
import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clicli_md3/services/app_updates.dart';
import 'package:clicli_md3/services/windows_updater.dart';
import 'package:clicli_md3/services/update_download.dart';
import 'app_updates_test.dart' as update_fixture;
import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/main.dart';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:clicli_md3/services/session_store.dart';
import 'package:clicli_md3/ui/detail_page.dart';
import 'package:clicli_md3/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sample = Anime(
  id: 42,
  name: '一部很长名字的测试番剧',
  status: '更新至第 8 集',
  year: '2026',
  area: '日本',
  description: '这是用于验证详情与界面的测试内容。',
  sources: [
    PlaySource('mao', '高速云', ['第01集', '第02集']),
  ],
);

class FakeApi extends ClicliApi {
  String? searched;
  @override
  Future<String> connect({String? cachedHost}) async {
    host = 'https://example.com';
    return host!;
  }

  @override
  Future<List<Channel>> channels() async => [
    const Channel(1, '日本动漫', genres: ['冒险'], years: ['2026'], areas: ['日本']),
  ];
  @override
  Future<List<Anime>> banners([int channel = 0]) async => [sample];
  @override
  Future<CatalogPage> list({
    int channel = 0,
    int page = 1,
    String sort = 'hits',
    String? year,
    String? genre,
    String? area,
  }) async => const CatalogPage([sample], 1);
  @override
  Future<CatalogPage> search(String keyword, {int page = 1}) async {
    searched = keyword;
    return const CatalogPage([sample], 1);
  }

  @override
  Future<Anime> detail(int id) async => sample;
}

class UiSessionStore implements SessionStore {
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

class CloudUiApi extends FakeApi {
  bool collected = true;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> login(String account, String password) async => {
    'token': 'fixture',
  };
  @override
  Future<Map<String, dynamic>> userInfo() async => {
    'id': 11,
    'user_name': '测试账号',
  };
  @override
  Future<void> logout() async {}
  @override
  Future<RecordPage<AccountHistory>> accountHistory({int page = 1}) async =>
      RecordPage([
        AccountHistory(
          77,
          WatchEntry(
            const Anime(id: 77, name: '云端历史样本'),
            'mao',
            '第02集',
            87,
            100,
            DateTime(2026),
          ),
        ),
      ], 1);
  @override
  Future<RecordPage<Anime>> accountFavorites({int page = 1}) async {
    reads++;
    return RecordPage(
      collected ? [const Anime(id: 77, name: '云端收藏样本')] : [],
      collected ? 1 : 0,
    );
  }

  @override
  Future<void> setAccountFavorite(int id, {required bool collected}) async {
    this.collected = collected;
  }

  @override
  Future<Anime> detail(int id) async => Anime(
    id: 77,
    name: '云端收藏样本',
    sources: sample.sources,
    accountResume: const AccountResume('mao', '第02集', 87, 100, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsUpdater.channel, (_) async => null);
  });
  testWidgets(
    'history and favorites default by login on entry and account changes',
    (tester) async {
      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CloudUiApi();
      final state = AppState(await SharedPreferences.getInstance());
      await state.toggleFavorite(const Anime(id: 1, name: '本地收藏样本'));
      await state.saveWatch(
        WatchEntry(
          const Anime(id: 1, name: '本地历史样本'),
          'mao',
          '第01集',
          10,
          100,
          DateTime(2026),
        ),
      );
      state.bindAccount(api, storage: UiSessionStore());
      await tester.pumpWidget(ClicliApp(state: state, api: api));
      await tester.pumpAndSettle();
      Future<void> navigate(String label) async {
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
      }

      bool remoteSelected() => tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .selected
          .single;
      await navigate('收藏');
      expect(remoteSelected(), false);
      expect(find.text('本地收藏样本'), findsOneWidget);
      await navigate('账号');
      expect(remoteSelected(), true);
      await navigate('发现');
      await navigate('收藏');
      expect(remoteSelected(), false);
      await state.account!.signIn('fixture', 'fixture');
      await tester.pumpAndSettle();
      expect(remoteSelected(), true);
      expect(find.text('云端收藏样本'), findsOneWidget);
      await navigate('本地');
      expect(find.text('本地收藏样本'), findsOneWidget);
      await navigate('发现');
      await navigate('收藏');
      expect(remoteSelected(), true);
      await navigate('观看历史');
      expect(remoteSelected(), true);
      expect(find.text('云端历史样本'), findsOneWidget);
      await navigate('本地');
      expect(find.text('本地历史样本'), findsOneWidget);
      await navigate('发现');
      await navigate('观看历史');
      expect(remoteSelected(), true);
      await state.account!.signOut();
      await tester.pumpAndSettle();
      expect(remoteSelected(), false);
      expect(find.text('本地历史样本'), findsOneWidget);
      await navigate('账号');
      await navigate('发现');
      await navigate('观看历史');
      expect(remoteSelected(), false);
      await state.account!.signIn('fixture', 'fixture');
      await tester.pumpAndSettle();
      expect(remoteSelected(), true);
      await navigate('收藏');
      await navigate('本地');
      await state.account!.signOut();
      await tester.pumpAndSettle();
      expect(remoteSelected(), false);
      expect(find.text('本地收藏样本'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      api.dispose();
    },
  );
  for (final size in [const Size(1360, 900), const Size(760, 580)]) {
    testWidgets(
      'cloud favorites, local isolation, remote resume and logout fit $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = CloudUiApi();
        final state = AppState(await SharedPreferences.getInstance());
        await state.toggleFavorite(const Anime(id: 1, name: '本地收藏样本'));
        state.bindAccount(api, storage: UiSessionStore());
        await tester.pumpWidget(ClicliApp(state: state, api: api));
        await tester.pumpAndSettle();
        await state.account!.signIn('fixture', 'fixture');
        await tester.pumpAndSettle();
        expect(state.favoritesSync!.items.keys, [77]);
        await tester.tap(find.text('收藏'));
        await tester.pumpAndSettle();
        expect(find.text('云端收藏样本'), findsOneWidget);
        expect(find.text('本地收藏样本'), findsNothing);
        await tester.tap(find.text('本地'));
        await tester.pumpAndSettle();
        expect(find.text('本地收藏样本'), findsOneWidget);
        await tester.tap(find.text('账号'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('云端收藏样本'));
        await tester.pumpAndSettle();
        expect(find.text('已收藏'), findsOneWidget);
        expect(find.text('继续观看'), findsOneWidget);
        expect(find.text('上次看到 第02集 · 01:27'), findsOneWidget);
        await tester.tap(find.text('已收藏'));
        await tester.pumpAndSettle();
        expect(api.collected, false);
        expect(state.favorites.keys, [1]);
        expect(find.text('收藏'), findsOneWidget);
        await state.account!.signOut();
        await tester.pumpAndSettle();
        expect(state.favoritesSync!.items, isEmpty);
        expect(find.text('上次看到 第02集 · 01:27'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        api.dispose();
      },
    );
  }
  testWidgets('favorite and follow badges use the matching icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 220,
                height: 320,
                child: AnimeCard(anime: sample, onTap: () {}, favorite: true),
              ),
              SizedBox(
                width: 220,
                height: 320,
                child: AnimeCard(anime: sample, onTap: () {}, saved: true),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.byTooltip('已收藏'), findsOneWidget);
    expect(find.byTooltip('已追番'), findsOneWidget);
  });
  testWidgets(
    'close hides immediately, awaits local persistence once and then exits natively',
    (tester) async {
      final state = AppState(await SharedPreferences.getInstance()),
          api = FakeApi();
      state.bindAccount(api, storage: UiSessionStore());
      final saved = Completer<void>();
      final calls = <String>[];
      const windowChannel = MethodChannel('window_manager');
      const nativeChannel = MethodChannel('CiliCiliWinRev/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        nativeChannel,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          nativeChannel,
          null,
        );
      });
      await tester.pumpWidget(ClicliApp(state: state, api: api));
      await tester.pumpAndSettle();
      state.flushPlayback = () async {
        calls.add('saveLocal');
        await saved.future;
      };
      windowManager.listeners.last.onWindowClose();
      windowManager.listeners.last.onWindowClose();
      await tester.pump();
      expect(calls, ['hide', 'saveLocal']);
      saved.complete();
      await tester.pumpAndSettle();
      expect(calls, ['hide', 'saveLocal', 'exitApplication']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'startup update prompt, settings toggle and manual check work with isolated session',
    (tester) async {
      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(await SharedPreferences.getInstance()),
          api = FakeApi();
      state.bindAccount(api, storage: UiSessionStore());
      var requests = 0, downloadRequests = 0;
      final updates = AppUpdates(
        state.preferences,
        currentVersion: '0.6.1',
        download: UpdateDownload(
          repository: 'WhiteBr1ck/CiliCiliWinRev',
          clientFactory: () => MockClient((_) async {
            downloadRequests++;
            return http.Response('', 503);
          }),
        ),
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(update_fixture.release()), 200);
        }),
      );
      await tester.pumpWidget(
        ClicliApp(state: state, api: api, updates: updates),
      );
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsOneWidget);
      expect(updates.download.received, 0);
      expect(downloadRequests, 0);
      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();
      expect(downloadRequests, 1);
      expect(find.text('重试更新'), findsOneWidget);
      expect(find.text('更新尚未准备就绪，请稍后重试'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('启动时检查更新'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('启动时检查更新'));
      await tester.pumpAndSettle();
      expect(updates.automatic, false);
      expect(state.preferences.getBool('automaticUpdates'), false);
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('新版本 0.7.0'), findsOneWidget);
      await tester.tap(find.text('更新至 0.7.0'));
      await tester.pumpAndSettle();
      expect(find.text('重试更新'), findsOneWidget);
      expect(updates.download.received, 0);
      expect(downloadRequests, 1);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      updates.dispose();
      api.dispose();
    },
  );
  for (final scenario in ['success', 'save-failure', 'commit-failure']) {
    final saveFails = scenario == 'save-failure';
    var commitFails = scenario == 'commit-failure';
    testWidgets(
      'update handoff waits for persistence and recovers: $scenario',
      (tester) async {
        SharedPreferences.setMockInitialValues({'automaticUpdates': false});
        final state = AppState(await SharedPreferences.getInstance());
        final api = FakeApi();
        state.bindAccount(api, storage: UiSessionStore());
        final updates = AppUpdates(state.preferences);
        final calls = <String>[];
        final saved = Completer<void>();
        const windowChannel = MethodChannel('window_manager');
        const exitChannel = MethodChannel('CiliCiliWinRev/window');
        final messenger = tester.binding.defaultBinaryMessenger;
        for (final channel in [
          windowChannel,
          exitChannel,
          WindowsUpdater.channel,
        ]) {
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'commit' && commitFails) {
              throw PlatformException(code: 'fixture', message: 'helper ended');
            }
            return null;
          });
        }
        addTearDown(() {
          for (final channel in [
            windowChannel,
            exitChannel,
            WindowsUpdater.channel,
          ]) {
            messenger.setMockMethodCallHandler(channel, null);
          }
          updates.dispose();
        });
        await tester.pumpWidget(
          ClicliApp(state: state, api: api, updates: updates),
        );
        await tester.pumpAndSettle();
        calls.clear();
        state.flushPlayback = () async {
          calls.add('saveLocal');
          await saved.future;
        };
        state.resumePlayback = () => calls.add('resumePlayback');
        Object? failure;
        final handoff = updates.download.shutdown!().catchError((Object e) {
          failure = e;
        });
        await tester.pump();
        expect(calls, ['saveLocal']);
        if (saveFails) {
          saved.completeError(StateError('fixture write failed'));
        } else {
          saved.complete();
        }
        await tester.pumpAndSettle();
        await handoff;
        if (saveFails || commitFails) {
          expect(calls, [
            'saveLocal',
            if (commitFails) 'commit',
            'resumePlayback',
          ]);
          expect(failure, isA<FormatException>());
          commitFails = false;
          state.flushPlayback = () async {
            calls.add('retrySave');
          };
          await updates.download.shutdown!();
          expect(calls, [
            'saveLocal',
            if (scenario == 'commit-failure') 'commit',
            'resumePlayback',
            'retrySave',
            'commit',
            'hide',
            'exitApplication',
          ]);
        } else {
          expect(calls, ['saveLocal', 'commit', 'hide', 'exitApplication']);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final size in [const Size(1360, 900), const Size(760, 580)]) {
    testWidgets('home, search, settings and library fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(await SharedPreferences.getInstance()),
          api = FakeApi();
      state.bindAccount(api, storage: UiSessionStore());
      await tester.pumpWidget(ClicliApp(state: state, api: api));
      await tester.pumpAndSettle();
      expect(find.text('开始观看'), findsOneWidget);
      expect(find.text('今天，想看点什么？'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const Key('search')), '从零');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.searched, '从零');
      expect(find.text('“从零”的搜索结果'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('收藏你的心头好'), findsNothing);
      expect(tester.takeException(), isNull);
      api.dispose();
    });
  }
  testWidgets('detail actions save favorites and follows', (tester) async {
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(await SharedPreferences.getInstance());
    final api = FakeApi();
    state.bindAccount(api, storage: UiSessionStore());
    await tester.pumpWidget(ClicliApp(state: state, api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始观看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(state.favorites.containsKey(42), true);
    expect(find.text('已收藏'), findsOneWidget);
    await tester.tap(find.text('追番'));
    await tester.pumpAndSettle();
    expect(state.following.containsKey(42), true);
    expect(find.text('第02集'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
  testWidgets('long series supports episode lookup and range selection', (
    tester,
  ) async {
    String selected = '';
    final source = PlaySource(
      'mao',
      '高速云',
      List.generate(1179, (i) => '第${(i + 1).toString().padLeft(2, '0')}集'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EpisodePicker(
              source: source,
              selected: '第1178集',
              onSelect: (s) => selected = s,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第1178集'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '108');
    await tester.pumpAndSettle();
    await tester.tap(find.text('第108集'));
    expect(selected, '第108集');
    expect(tester.takeException(), isNull);
  });
  testWidgets('MD3 menu supports keyboard selection and bounded scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selections = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMenu<int>(
              label: '测试菜单',
              value: 0,
              items: {for (int i = 0; i < 40; i++) i: '选项 $i'},
              onSelected: selections.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选项 0'));
    await tester.pumpAndSettle();
    final scrollRect = tester.getRect(find.byType(SingleChildScrollView));
    expect(scrollRect.height, lessThanOrEqualTo(340));
    expect(scrollRect.top, greaterThanOrEqualTo(0));
    expect(scrollRect.bottom, lessThanOrEqualTo(580));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selections, hasLength(1));
    expect(find.byType(MenuItemButton), findsNothing);
    await tester.tap(find.text('选项 0'));
    await tester.pumpAndSettle();
    final lastItem = find.widgetWithText(MenuItemButton, '选项 39');
    await tester.ensureVisible(lastItem);
    await tester.pumpAndSettle();
    await tester.tap(lastItem);
    await tester.pumpAndSettle();
    expect(selections, hasLength(2));
    expect(selections.last, 39);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
