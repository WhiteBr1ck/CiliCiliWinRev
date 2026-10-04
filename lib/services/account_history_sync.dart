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
    final token = api.token;
    return token == null || token.isEmpty
        ? null
        : sha256.convert(utf8.encode(token)).toString();
  }

  String _key(String owner, WatchEntry entry) =>
      '$owner|${entry.anime.id}|${entry.source}|${entry.episode}';
  int get pendingCount => _pending.length;
  void _accountChanged() {
    if (account.loggedIn) unawaited(flush());
  }

  void pause() => _paused = true;

  Future<void> enqueue(WatchEntry entry, {bool transmit = true}) async {
    final owner = _owner;
    if (_disposed ||
        owner == null ||
        entry.anime.id <= 0 ||
        entry.position <= 0) {
      return;
    }
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
      final rows = _pending.entries.where((e) => e.value.account == owner);
      if (owner == null || rows.isEmpty) return;
      final row = rows.first;
      try {
        await api
            .saveAccountHistory(row.value.entry)
            .timeout(const Duration(seconds: 3));
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
        error = '$e';
        _notify();
        return;
      }
      _notify();
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
