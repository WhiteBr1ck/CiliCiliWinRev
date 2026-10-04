import 'dart:async';
import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/models.dart';
import 'package:clicli_md3/services/account_favorites_sync.dart';
import 'package:clicli_md3/services/account_session.dart';
import 'package:clicli_md3/services/clicli_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_ui_test.dart' show MemorySessionStore;

class CollectionApi extends ClicliApi {
  final requests = <({String? token, int page})>[];
  final changes = <({int id, bool collected})>[];
  Future<RecordPage<Anime>> Function(int)? read;
  Future<void> Function()? write;
  Future<Map<String, dynamic>> Function()? info;
  @override
  Future<Map<String, dynamic>> userInfo() async =>
      info == null ? {'id': token == 'bob' ? 2 : 1} : await info!();
  @override
  Future<Map<String, dynamic>> login(String account, String password) async => {
    'token': account,
  };
  @override
  Future<void> logout() async {}
  @override
  Future<RecordPage<Anime>> accountFavorites({int page = 1}) async {
    requests.add((token: token, page: page));
    return read == null ? const RecordPage([], 0) : await read!(page);
  }

  @override
  Future<void> setAccountFavorite(int id, {required bool collected}) async {
    changes.add((id: id, collected: collected));
    await write?.call();
  }
}

const cloudAnime = Anime(id: 42, name: '账号收藏');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'a late profile from an earlier login cannot replace the active account identity',
    () async {
      final delayed = Completer<Map<String, dynamic>>();
      final api = CollectionApi();
      api.info = () => api.token == 'alice'
          ? delayed.future
          : Future.value({'id': 2, 'user_name': 'Bob'});
      final account = AccountSession(api, storage: MemorySessionStore());
      final first = account.signIn('alice', 'fixture');
      final rejected = expectLater(first, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      await account.signIn('bob', 'fixture');
      final owner = account.syncOwner;
      delayed.complete({'id': 1, 'user_name': 'Alice'});
      await rejected;
      expect(account.name, 'Bob');
      expect(account.syncOwner, owner);
      expect(api.token, 'bob');
      account.dispose();
      api.dispose();
    },
  );
  test(
    'session expiry clears collection and discards a late response',
    () async {
      final delayed = Completer<RecordPage<Anime>>();
      final api = CollectionApi()
        ..token = 'alice'
        ..read = (_) => delayed.future;
      final account = AccountSession(api, storage: MemorySessionStore());
      final sync = AccountFavoritesSync(api, account);
      final read = sync.refresh();
      api.token = null;
      api.onSessionExpired!();
      delayed.complete(const RecordPage([cloudAnime], 1));
      await read;
      expect(sync.items, isEmpty);
      expect(sync.busy, false);
      expect(sync.loaded, false);
      sync.dispose();
      account.dispose();
      api.dispose();
    },
  );
  test(
    'overlapping pagination never stops before the total number of unique videos',
    () async {
      final api = CollectionApi()..token = 'alice';
      api.read = (page) async => switch (page) {
        1 => const RecordPage([
          Anime(id: 1, name: '一'),
          Anime(id: 2, name: '二'),
        ], 3),
        2 => const RecordPage([
          Anime(id: 2, name: '二'),
          Anime(id: 3, name: '三'),
        ], 3),
        _ => const RecordPage([], 3),
      };
      final sync = AccountFavoritesSync(
        api,
        AccountSession(api, storage: MemorySessionStore()),
      );
      await sync.refresh();
      expect(sync.items.keys, [1, 2, 3]);
      expect(sync.error, isEmpty);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'restoration loads every page and never overwrites local favorites',
    () async {
      final api = CollectionApi();
      api.read = (page) async => page == 1
          ? const RecordPage([cloudAnime], 2)
          : const RecordPage([Anime(id: 43, name: '第二页')], 2);
      final store = MemorySessionStore()..token = 'alice';
      final state = AppState(await SharedPreferences.getInstance());
      await state.toggleFavorite(const Anime(id: 1, name: '本地收藏'));
      state.bindAccount(api, storage: store);
      await state.account!.restore();
      await state.favoritesSync!.refresh();
      expect(api.requests.map((r) => r.page), [1, 2]);
      expect(state.visibleFavorites.keys, [42, 43]);
      expect(state.favorites.keys, [1]);
      expect(api.changes, isEmpty);
      state.selectFavorites(false);
      expect(state.visibleFavorites.keys, [1]);
      state.dispose();
      api.dispose();
    },
  );
  test('mutations wait for success and failures remain retryable', () async {
    final api = CollectionApi()..token = 'alice';
    final account = AccountSession(api, storage: MemorySessionStore());
    final sync = AccountFavoritesSync(api, account);
    await sync.refresh();
    final wait = Completer<void>();
    api.write = () => wait.future;
    final saving = sync.toggle(cloudAnime);
    expect(sync.busy, true);
    expect(sync.items, isEmpty);
    wait.complete();
    await saving;
    expect(sync.items.keys, [42]);
    api.write = () async => throw const ApiException('offline');
    await expectLater(sync.toggle(cloudAnime), throwsA(isA<ApiException>()));
    expect(sync.items.keys, [42]);
    expect(sync.error, 'offline');
    api.write = null;
    await sync.toggle(cloudAnime);
    expect(sync.items, isEmpty);
    expect(api.changes.map((r) => r.collected), [true, false, false]);
    sync.dispose();
    api.dispose();
  });
  test(
    'switching accounts rejects late pages and clears the old collection',
    () async {
      final old = Completer<RecordPage<Anime>>();
      final api = CollectionApi();
      api.read = (_) => api.token == 'alice'
          ? old.future
          : Future.value(const RecordPage([Anime(id: 77, name: 'Bob')], 1));
      final account = AccountSession(api, storage: MemorySessionStore());
      final sync = AccountFavoritesSync(api, account);
      await account.signIn('alice', 'fixture');
      await account.signIn('bob', 'fixture');
      await sync.refresh();
      old.complete(const RecordPage([cloudAnime], 1));
      await Future<void>.delayed(Duration.zero);
      expect(sync.items.keys, [77]);
      await account.signOut();
      expect(sync.items, isEmpty);
      expect(sync.loaded, false);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'failed later pages keep the previous complete list and can refresh',
    () async {
      final api = CollectionApi()..token = 'alice';
      api.read = (_) async => const RecordPage([cloudAnime], 1);
      final sync = AccountFavoritesSync(
        api,
        AccountSession(api, storage: MemorySessionStore()),
      );
      await sync.refresh();
      api.read = (page) async {
        if (page == 2) throw const ApiException('offline');
        return const RecordPage([Anime(id: 43, name: '新数据')], 2);
      };
      await sync.refresh();
      expect(sync.items.keys, [42]);
      expect(sync.error, 'offline');
      api.read = (_) async => const RecordPage([], 0);
      await sync.refresh();
      expect(sync.items, isEmpty);
      expect(sync.error, isEmpty);
      sync.dispose();
      api.dispose();
    },
  );
  test(
    'missing totals paginate to exhaustion; repeated pages are errors',
    () async {
      final api = CollectionApi()..token = 'alice';
      api.read = (page) async => page <= 2
          ? RecordPage([Anime(id: page, name: '$page')], 0)
          : const RecordPage([], 0);
      final sync = AccountFavoritesSync(
        api,
        AccountSession(api, storage: MemorySessionStore()),
      );
      await sync.refresh();
      expect(api.requests.map((r) => r.page), [1, 2, 3]);
      expect(sync.items.keys, [1, 2]);
      api.read = (_) async => const RecordPage([cloudAnime], 0);
      await sync.refresh();
      expect(sync.error, contains('分页重复'));
      expect(sync.items.keys, [1, 2]);
      sync.dispose();
      api.dispose();
    },
  );
}
