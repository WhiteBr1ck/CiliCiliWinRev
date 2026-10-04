import 'dart:async';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/account_history_sync.dart';
import 'package:clicli_md3/services/account_session.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:clicli_md3/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncMemoryStore implements SessionStore {
  final String? token;
  SyncMemoryStore([this.token]);
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

class SyncFixtureApi extends ClicliApi {
  final sent = <WatchEntry>[];
  int? accountId;
  String loginToken = 'fixture';
  final deleted = <int>[];
  final events = <String>[];
  @override
  Future<Map<String, dynamic>> userInfo() async => {
    'user_name': 'fixture',
    if (accountId != null) 'id': accountId,
  };
  @override
  Future<Map<String, dynamic>> login(String account, String password) async => {
    'token': loginToken,
  };
  @override
  Future<void> logout() async {}
  @override
  Future<void> deleteAccountHistory(int id) async {
    deleted.add(id);
    events.add('delete');
  }

  Future<void> Function(WatchEntry)? send;
  @override
  Future<void> saveAccountHistory(WatchEntry entry) async {
    sent.add(entry);
    events.add('post');
    await send?.call(entry);
    events.add('posted');
  }
}

WatchEntry entry(int position) => WatchEntry(
  const Anime(id: 42, name: '测试'),
  'mao',
  '第01集',
  position,
  1200,
  DateTime(2026, 10, 4),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'progress survives a new token for the same verified account ID only',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final api = SyncFixtureApi()
        ..accountId = 11
        ..loginToken = 'alice-old';
      final account = AccountSession(api, storage: SyncMemoryStore());
      final sync = AccountHistorySync(api, account, prefs);
      await account.signIn('fixture', 'fixture');
      await sync.enqueue(entry(90), transmit: false);
      await account.signOut();
      api.accountId = 22;
      api.loginToken = 'bob';
      await account.signIn('fixture', 'fixture');
      await sync.flush();
      expect(api.sent, isEmpty);
      expect(sync.pendingCount, 1);
      api.accountId = 11;
      api.loginToken = 'alice-new';
      await account.signIn('fixture', 'fixture');
      await sync.flush();
      expect(api.sent.single.position, 90);
      expect(sync.pendingCount, 0);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'legacy token queue migrates only when restoring that token with a verified ID',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final api = SyncFixtureApi()..token = 'legacy';
      final legacy = AccountHistorySync(
        api,
        AccountSession(api, storage: SyncMemoryStore()),
        prefs,
      );
      await legacy.enqueue(entry(91), transmit: false);
      legacy.dispose();
      api.accountId = 11;
      final account = AccountSession(api, storage: SyncMemoryStore('legacy'));
      final sync = AccountHistorySync(api, account, prefs);
      await account.restore();
      await sync.flush();
      expect(api.sent.single.position, 91);
      expect(sync.pendingCount, 0);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'deletion waits for an earlier write and removes queued progress for that video',
    () async {
      final first = Completer<void>();
      final api = SyncFixtureApi()
        ..token = 'fixture'
        ..send = (_) => first.future;
      final sync = AccountHistorySync(
        api,
        AccountSession(api, storage: SyncMemoryStore()),
        await SharedPreferences.getInstance(),
      );
      await sync.enqueue(entry(70));
      await sync.enqueue(entry(90), transmit: false);
      final deletion = sync.delete(42);
      await Future<void>.delayed(Duration.zero);
      expect(api.deleted, isEmpty);
      await sync.enqueue(entry(100));
      first.complete();
      await deletion;
      await sync.flush();
      expect(api.events, ['post', 'posted', 'delete']);
      expect(api.deleted, [42]);
      expect(sync.pendingCount, 0);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'close checkpoints persist without HTTP and restore for later transmission',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final api = SyncFixtureApi()..token = 'fixture-account-token';
      final account = AccountSession(api, storage: SyncMemoryStore());
      final sync = AccountHistorySync(api, account, prefs);
      await sync.enqueue(entry(123), transmit: false);
      expect(api.sent, isEmpty);
      expect(sync.pendingCount, 1);
      expect(
        prefs.getString(AccountHistorySync.preferenceKey),
        isNot(contains('fixture-account-token')),
      );
      sync.dispose();
      final restored = AccountHistorySync(api, account, prefs);
      await restored.flush();
      expect(api.sent.single.position, 123);
      expect(restored.pendingCount, 0);
      restored.dispose();
      api.dispose();
    },
  );
  test(
    'an in-flight cloud request cannot block a newer close checkpoint or clear it',
    () async {
      final first = Completer<void>(), second = Completer<void>();
      final api = SyncFixtureApi()..token = 'fixture';
      api.send = (_) => api.sent.length == 1 ? first.future : second.future;
      final sync = AccountHistorySync(
        api,
        AccountSession(api, storage: SyncMemoryStore()),
        await SharedPreferences.getInstance(),
      );
      await sync.enqueue(entry(50));
      expect(api.sent.single.position, 50);
      await sync.enqueue(entry(60), transmit: false);
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(api.sent.last.position, 60);
      expect(sync.pendingCount, 1);
      second.complete();
      await sync.flush();
      expect(sync.pendingCount, 0);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'queued progress is never submitted under another login session',
    () async {
      final api = SyncFixtureApi()..token = 'alice-fixture';
      final account = AccountSession(api, storage: SyncMemoryStore());
      final sync = AccountHistorySync(
        api,
        account,
        await SharedPreferences.getInstance(),
      );
      await sync.enqueue(entry(90), transmit: false);
      api.token = 'bob-fixture';
      await sync.flush();
      expect(api.sent, isEmpty);
      expect(sync.pendingCount, 1);
      api.token = 'alice-fixture';
      await account.restore();
      // restore uses the injected store and signs out; no real account is loaded.
      api.token = 'alice-fixture';
      await sync.flush();
      expect(api.sent.single.position, 90);
      sync.dispose();
      api.dispose();
    },
  );
  test('unchanged playback positions are not posted repeatedly', () async {
    final api = SyncFixtureApi()..token = 'fixture';
    final sync = AccountHistorySync(
      api,
      AccountSession(api, storage: SyncMemoryStore()),
      await SharedPreferences.getInstance(),
    );
    await sync.enqueue(entry(80));
    await sync.flush();
    await sync.enqueue(entry(80));
    await sync.flush();
    expect(api.sent, hasLength(1));
    sync.dispose();
    api.dispose();
  });
  test(
    'failed sends retain progress; paused shutdown never starts more requests',
    () async {
      final api = SyncFixtureApi()..token = 'fixture';
      api.send = (_) async => throw const ApiException('offline');
      final sync = AccountHistorySync(
        api,
        AccountSession(api, storage: SyncMemoryStore()),
        await SharedPreferences.getInstance(),
      );
      await sync.enqueue(entry(120), transmit: false);
      await sync.flush();
      expect(sync.pendingCount, 1);
      expect(sync.error, 'offline');
      sync.pause();
      await sync.enqueue(entry(125));
      await sync.flush();
      expect(api.sent, hasLength(1));
      sync.dispose();
      api.dispose();
    },
  );
}
