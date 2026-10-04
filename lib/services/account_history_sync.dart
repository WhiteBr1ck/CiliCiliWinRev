import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'account_session.dart';
import 'clicli_api.dart';

/// Durable progress outbox. Closing saves locally without waiting for HTTP.
class AccountHistorySync extends ChangeNotifier {
  final ClicliApi api;
  final AccountSession account;
  final SharedPreferences preferences;
  final _pending = <String, ({String account, WatchEntry entry})>{};
  final _confirmed = <String, int>{};
  final _deleting = <String>{};
  Future<void> _writes = Future.value();
  Future<void>? _draining;
  bool _paused = false, _disposed = false;
  String error = '';
  static const preferenceKey = 'pendingAccountHistory';
  AccountHistorySync(this.api, this.account, this.preferences) {
    try {
      final rows =
          jsonDecode(preferences.getString(preferenceKey) ?? '[]') as List;
      for (final row in rows.whereType<Map>().take(50)) {
        final owner = '${row['account']}';
        final entry = WatchEntry.fromJson(
          Map<String, dynamic>.from(row['entry']),
        );
        if (RegExp(r'^[a-f0-9]{64}$').hasMatch(owner) &&
            entry.anime.id > 0 &&
            entry.position > 0) {
          _pending[_key(owner, entry)] = (account: owner, entry: entry);
        }
      }
    } catch (_) {}
    account.addListener(_accountChanged);
  }

  String? get _owner {
    return account.syncOwner;
  }

  String _key(String owner, WatchEntry entry) =>
      '$owner|${entry.anime.id}|${entry.source}|${entry.episode}';
  int get pendingCount => _pending.length;
  void _accountChanged() {
    if (!account.loggedIn) return;
    final tokenOwner = sha256.convert(utf8.encode(api.token!)).toString();
    final owner = _owner!;
    if (owner != tokenOwner) {
      // Upgrade only entries proven to belong to the currently restored token.
      final legacy = _pending.entries
          .where((e) => e.value.account == tokenOwner)
          .toList();
      for (final row in legacy) {
        _pending.remove(row.key);
        final key = _key(owner, row.value.entry);
        final existing = _pending[key]?.entry;
        final entry = row.value.entry;
        if (existing == null ||
            (entry.updated ?? DateTime(1970)).isAfter(
              existing.updated ?? DateTime(1970),
            )) {
          _pending[key] = (account: owner, entry: entry);
        }
      }
      if (legacy.isNotEmpty) unawaited(_persist());
    }
    unawaited(flush());
  }

  void pause() => _paused = true;
  void resume() => _paused = false;

  Future<void> enqueue(WatchEntry entry, {bool transmit = true}) async {
    final owner = _owner;
    if (_disposed ||
        owner == null ||
        entry.anime.id <= 0 ||
        entry.position <= 0) {
      return;
    }
    if (_deleting.contains('$owner|${entry.anime.id}')) return;
    final key = _key(owner, entry);
    if (_pending[key]?.entry.position == entry.position) {
      await _writes;
      if (transmit) unawaited(flush());
      return;
    }
    if (!_pending.containsKey(key) && _confirmed[key] == entry.position) {
      await _writes;
      return;
    }
    _pending.remove(key);
    _pending[key] = (account: owner, entry: entry);
    while (_pending.length > 50) {
      _pending.remove(_pending.keys.first);
    }
    await _persist();
    if (transmit) unawaited(flush());
  }

  Future<void> _persist() {
    final value = jsonEncode([
      for (final row in _pending.values)
        {'account': row.account, 'entry': row.entry.toJson()},
    ]);
    return _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString(preferenceKey, value)) {
        throw StateError('无法保存待同步的观看进度');
      }
    });
  }

  Future<void> flush() {
    if (_paused || _disposed || _owner == null) return Future.value();
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    while (!_paused && !_disposed) {
      final owner = _owner;
      final rows = _pending.entries.where(
        (e) =>
            e.value.account == owner &&
            !_deleting.contains('$owner|${e.value.entry.anime.id}'),
      );
      if (owner == null || rows.isEmpty) return;
      final row = rows.first;
      try {
        // Do not abandon a live write after a shorter wrapper timeout: it could
        // arrive after a newer progress write or a history deletion.
        await api.saveAccountHistory(row.value.entry);
        if (_disposed) return;
        _confirmed[row.key] = row.value.entry.position;
        while (_confirmed.length > 50) {
          _confirmed.remove(_confirmed.keys.first);
        }
        // A later position queued during this request must remain pending.
        if (identical(_pending[row.key]?.entry, row.value.entry)) {
          _pending.remove(row.key);
          await _persist();
        }
        error = '';
      } catch (e) {
        if (_disposed) return;
        if (_owner != owner) continue;
        error = '$e';
        _notify();
        return;
      }
      _notify();
    }
  }

  WatchEntry? pendingFor(int video) {
    final entries =
        _pending.values
            .where((r) => r.account == _owner && r.entry.anime.id == video)
            .map((r) => r.entry)
            .toList()
          ..sort(
            (a, b) => (b.updated ?? DateTime(1970)).compareTo(
              a.updated ?? DateTime(1970),
            ),
          );
    return entries.firstOrNull;
  }

  Future<void> delete(int video) async {
    final owner = _owner, token = api.token;
    if (owner == null) throw const ApiException('请先登录');
    final key = '$owner|$video';
    if (!_deleting.add(key)) return;
    try {
      // Finish any earlier write before deleting, so it cannot recreate the row.
      await _draining;
      if (_disposed || token != api.token) {
        throw const ApiException('账号已切换，请重试');
      }
      await api.deleteAccountHistory(video);
      _pending.removeWhere(
        (k, row) => row.account == owner && row.entry.anime.id == video,
      );
      _confirmed.removeWhere((k, _) => k.startsWith('$owner|$video|'));
      await _persist();
    } finally {
      _deleting.remove(key);
    }
  }

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
