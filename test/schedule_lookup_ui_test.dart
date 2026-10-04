import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:clicli_md3/services/session_store.dart';
import 'package:clicli_md3/ui/components.dart';
import 'package:clicli_md3/ui/detail_page.dart';
import 'package:clicli_md3/ui/schedule_lookup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LookupApi extends ClicliApi {
  Anime? result;
  bool fail = false;
  @override
  Future<Anime?> scheduledAnime(ScheduleEntry entry) async {
    if (fail) throw const ApiException('连接失败');
    return result;
  }

  @override
  Future<Anime> detail(int id) async => result!;
}

class LookupSessionStore implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const entry = ScheduleEntry(
    Anime(id: -1, name: '季度作品', year: '2026'),
    1,
    '22:00',
  );
  Future<void> show(WidgetTester tester, LookupApi api) async {
    final state = AppState(await SharedPreferences.getInstance());
    state.bindAccount(api, storage: LookupSessionStore());
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleLookupPage(entry: entry, api: api, state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('missing catalog entry shows exactly the requested single line', (
    tester,
  ) async {
    await show(tester, LookupApi());
    expect(find.text('CliCli没有该影片'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
    expect(find.byType(DetailPage), findsNothing);
  });
  testWidgets(
    'network error is retriable and never states that the film is absent',
    (tester) async {
      final api = LookupApi()..fail = true;
      await show(tester, api);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('CliCli没有该影片'), findsNothing);
      api.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('CliCli没有该影片'), findsOneWidget);
    },
  );
  testWidgets(
    'available schedule selection opens catalog detail and episodes',
    (tester) async {
      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(
        tester,
        LookupApi()
          ..result = const Anime(
            id: 12,
            name: '季度作品',
            sources: [
              PlaySource('mao', '高速云', ['第01集']),
            ],
          ),
      );
      expect(find.byType(DetailPage), findsOneWidget);
      expect(find.byType(EpisodePicker), findsOneWidget);
      expect(find.text('CliCli没有该影片'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
