import 'dart:convert';
import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clicli_md3/services/app_updates.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
      var requests = 0;
      final updates = AppUpdates(
        state.preferences,
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(update_fixture.release()), 200);
        }),
      );
      await tester.pumpWidget(
        ClicliApp(state: state, api: api, updates: updates),
      );
      await tester.pumpAndSettle();
      expect(find.text('新版本 0.7.0'), findsOneWidget);
      expect(find.text('下载安装包'), findsOneWidget);
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
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      updates.dispose();
      api.dispose();
    },
  );
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
