import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/account_session.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:clicli_md3/ui/account_dialog.dart';
import 'package:clicli_md3/ui/community_panel.dart';
import 'package:clicli_md3/ui/history_page.dart';
import 'package:clicli_md3/ui/timetable_page.dart';
import 'package:clicli_md3/theme.dart';
import 'package:flutter/material.dart';
import 'package:clicli_md3/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountFixtureApi extends ClicliApi {
  List<AccountHistory>? historyFixture;
  int logins = 0, registrations = 0, sent = 0, posted = 0;
  int durationReads = 0;
  @override
  Future<int?> episodeDuration(WatchEntry entry) async {
    durationReads++;
    return 1000;
  }

  @override
  Future<Map<String, dynamic>> login(String account, String password) async {
    logins++;
    return {'token': 'fixture'};
  }

  @override
  Future<Map<String, dynamic>> userInfo() async => {'user_name': '测试账号'};
  @override
  Future<void> register({
    required String nickname,
    required String email,
    required String password,
    required String code,
  }) async {
    registrations++;
  }

  @override
  Future<void> sendCode(
    String email,
    String type, {
    String uuid = '',
    String dots = '',
  }) async {
    sent++;
  }

  @override
  Future<void> logout() async {}
  @override
  Future<RecordPage<AccountHistory>> accountHistory({int page = 1}) async =>
      RecordPage(
        historyFixture ??
            [
              AccountHistory(
                42,
                WatchEntry(
                  const Anime(id: 42, name: '账号历史'),
                  'mao',
                  '第02集',
                  120,
                  0,
                  DateTime(2026),
                ),
              ),
            ],
        historyFixture?.length ?? 1,
      );
  @override
  Future<RecordPage<VodComment>> vodComments(int id, {int page = 1}) async =>
      const RecordPage([
        VodComment(
          id: 7,
          name: '测试用户',
          text: '真实接口格式的测试评论',
          date: '2026-10-04',
        ),
      ], 1);
  @override
  Future<void> postComment(
    int id,
    String text, {
    int lastId = 0,
    String uuid = '',
    String dots = '',
  }) async {
    posted++;
  }

  @override
  Future<TimetableBatch> timetable(
    int year, {
    int batch = 1,
    int quarter = 1,
  }) async => TimetableBatch([
    const ScheduleEntry(Anime(id: 42, name: '周一番剧'), 1, '21:30'),
  ]);
}

class MemorySessionStore implements SessionStore {
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('session restores token, signs out and never saves password', () async {
    final api = AccountFixtureApi();
    final storage = MemorySessionStore();
    final account = AccountSession(api, storage: storage);
    await account.signIn('fixture@example.com', 'test-password');
    expect(account.name, '测试账号');
    expect(account.loggedIn, true);
    expect(await storage.read(), 'fixture');
    api.token = null;
    final restored = AccountSession(api, storage: storage);
    await restored.restore();
    expect(restored.loggedIn, true);
    await restored.signOut();
    expect(restored.loggedIn, false);
    expect(await storage.read(), isNull);
    api.dispose();
  });
  for (final size in [const Size(1360, 900), const Size(760, 580)]) {
    testWidgets('login and registration forms fit $size and validate', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AccountFixtureApi(),
          account = AccountSession(
            AccountFixtureApi(),
            storage: MemorySessionStore(),
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.make(Brightness.light),
          home: Scaffold(body: AccountDialog(account: account)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();
      expect(find.text('请填写此项'), findsWidgets);
      expect(api.registrations, 0);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'jskdfjkf');
      await tester.enterText(fields.at(1), 'test@example.com');
      await tester.enterText(fields.at(2), '1234');
      await tester.enterText(fields.at(3), '123456');
      await tester.enterText(fields.at(4), '123456');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.ensureVisible(find.widgetWithText(FilledButton, '注册'));
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();
      expect((account.api as AccountFixtureApi).registrations, 0);
      expect(find.text('昵称请使用 1 至 12 个汉字，不含字母、数字或符号'), findsOneWidget);
      await tester.enterText(fields.at(0), '昵称');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '注册'));
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();
      expect(find.text('注册成功，请登录'), findsOneWidget);
      expect((account.api as AccountFixtureApi).registrations, 1);
      expect(tester.takeException(), isNull);
      api.dispose();
      account.api.dispose();
    });
  }
  testWidgets('local and account history stay separate', (tester) async {
    final state = AppState(await SharedPreferences.getInstance()),
        api = AccountFixtureApi();
    state.bindAccount(api, storage: MemorySessionStore());
    await state.saveWatch(
      WatchEntry(
        const Anime(id: 1, name: '本地历史'),
        'mao',
        '第01集',
        10,
        100,
        DateTime(2026),
      ),
    );
    api.token = 'fixture';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryPage(state: state, api: api, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('账号历史'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('history-progress-42')),
          )
          .value,
      closeTo(.12, .001),
    );
    expect(find.text('本地历史'), findsNothing);
    await tester.tap(find.text('本地'));
    await tester.pumpAndSettle();
    expect(find.text('本地历史'), findsOneWidget);
    api.dispose();
  });
  testWidgets(
    'account timeline groups dates, orders records and preserves unknown time',
    (tester) async {
      final api = AccountFixtureApi();
      api.token = 'fixture';
      api.historyFixture = [
        AccountHistory(
          1,
          WatchEntry(
            const Anime(id: 1, name: '昨天的作品'),
            'mao',
            '第01集',
            123,
            0,
            DateTime(2026, 10, 3, 21, 15),
          ),
        ),
        AccountHistory(
          2,
          WatchEntry(
            const Anime(id: 2, name: '今天的作品'),
            'mao',
            '第02集',
            200,
            0,
            DateTime(2026, 10, 4, 10, 30),
          ),
        ),
        AccountHistory(
          3,
          WatchEntry(
            const Anime(id: 3, name: '旧记录'),
            'mao',
            '第03集',
            250,
            0,
            null,
          ),
        ),
      ];
      final state = AppState(await SharedPreferences.getInstance())
        ..bindAccount(api, storage: MemorySessionStore());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryPage(state: state, api: api, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-10-04'), findsOneWidget);
      expect(find.textContaining('2026-10-03'), findsOneWidget);
      expect(find.text('观看于 10:30'), findsOneWidget);
      expect(find.text('观看于 21:15'), findsOneWidget);
      expect(find.text('时间未知'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      expect(find.textContaining('2000-01-01'), findsNothing);
      expect(
        tester.getTopLeft(find.text('今天的作品')).dy,
        lessThan(tester.getTopLeft(find.text('昨天的作品')).dy),
      );
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );
  testWidgets('comments load and timetable opens actual scheduled entry', (
    tester,
  ) async {
    final api = AccountFixtureApi(),
        state = AppState(await SharedPreferences.getInstance());
    state.bindAccount(api, storage: MemorySessionStore());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityPanel(api: api, state: state, videoId: 42),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('真实接口格式的测试评论'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimetablePage(api: api, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '周一'));
    await tester.pumpAndSettle();
    expect(find.text('21:30'), findsOneWidget);
    expect(find.text('周一番剧'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.dispose();
  });
}
