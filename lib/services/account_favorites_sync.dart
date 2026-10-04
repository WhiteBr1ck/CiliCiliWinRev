import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models.dart';
import 'account_session.dart';
import 'clicli_api.dart';

/// Server-owned collection, kept separate from the device's local favorites.
class AccountFavoritesSync extends ChangeNotifier {
  final ClicliApi api;
  final AccountSession account;
  final Map<int, Anime> items = {};
  final Set<int> _changing = {};
  String error = '';
  bool loading = false, loaded = false, _disposed = false;
  int _generation = 0;
  String? _token;
  Future<void>? _loading;
  AccountFavoritesSync(this.api, this.account) {
    account.addListener(_accountChanged);
  }

  bool get busy => loading || _changing.isNotEmpty;
  void _accountChanged() {
    if (_token == api.token) return;
    _generation++;
    _token = api.token;
    _loading = null;
    items.clear();
    _changing.clear();
    loading = loaded = false;
    error = '';
    _notify();
    if (account.loggedIn) unawaited(refresh());
  }

  Future<void> refresh() {
    if (_disposed || !account.loggedIn) return Future.value();
    if (_changing.isNotEmpty) return Future.value();
    if (_token != api.token) {
      _accountChanged();
      return _loading ?? Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final generation = ++_generation, token = api.token;
    loading = true;
    error = '';
    _notify();
    try {
      final collected = <int, Anime>{};
      for (var page = 1; ; page++) {
        final result = await api.accountFavorites(page: page);
        if (!_current(generation, token)) return;
        final before = collected.length;
        for (final anime in result.items) {
          if (anime.id > 0) collected[anime.id] = anime;
        }
        if (result.items.isEmpty) break;
        if (collected.length == before) {
          throw const ApiException('收藏分页重复，请刷新重试');
        }
        if (result.total > 0 && collected.length >= result.total) break;
      }
      items
        ..clear()
        ..addAll(collected);
      loaded = true;
    } catch (e) {
      if (_current(generation, token)) error = '$e';
    } finally {
      if (_current(generation, token)) {
        loading = false;
        _loading = null;
        _notify();
      }
    }
  }

  Future<void> toggle(Anime anime) async {
    if (!account.loggedIn) throw const ApiException('请先登录');
    if (_changing.isNotEmpty) return;
    final token = api.token;
    // Wait for the full collection before deciding whether to add or remove.
    if (loading || !loaded) await refresh();
    if (_disposed || api.token != token) {
      throw const ApiException('账号已切换，请重试');
    }
    if (!loaded) {
      throw ApiException(error.isEmpty ? '收藏未加载，请刷新重试' : error);
    }
    if (busy) return;
    final collected = !items.containsKey(anime.id);
    final generation = _generation;
    _changing.add(anime.id);
    _notify();
    try {
      await api.setAccountFavorite(anime.id, collected: collected);
      if (!_current(generation, token)) return;
      collected ? items[anime.id] = anime : items.remove(anime.id);
      error = '';
    } catch (e) {
      if (_current(generation, token)) error = '$e';
      rethrow;
    } finally {
      if (_current(generation, token)) {
        _changing.remove(anime.id);
        _notify();
      }
    }
  }

  bool _current(int generation, String? token) =>
      !_disposed && generation == _generation && token == api.token;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    account.removeListener(_accountChanged);
    super.dispose();
  }
}
