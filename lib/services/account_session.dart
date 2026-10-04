import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'clicli_api.dart';
import 'session_store.dart';

class AccountSession extends ChangeNotifier {
  final ClicliApi api;
  final SessionStore storage;
  Map<String, dynamic> profile = {};
  String? _profileToken;
  int _generation = 0;
  bool restored = false;
  String status = '';
  AccountSession(this.api, {this.storage = const WindowsSessionStore()}) {
    api.onSessionExpired = () {
      _generation++;
      profile = {};
      _profileToken = null;
      status = '登录已失效';
      notifyListeners();
      storage.delete().catchError((_) {});
    };
  }
  bool get loggedIn => api.token?.isNotEmpty == true;
  String? get syncOwner {
    if (!loggedIn) return null;
    // The original users/info response identifies the account with `id`.
    final id = _profileToken == api.token ? '${profile['id'] ?? ''}' : '';
    return sha256
        .convert(
          utf8.encode(
            RegExp(r'^[1-9]\d*$').hasMatch(id)
                ? 'clicli-account:$id'
                : api.token!,
          ),
        )
        .toString();
  }

  String get name =>
      '${profile['user_name'] ?? profile['uname'] ?? profile['nickname'] ?? '账号'}';
  Future<void> restore() async {
    if (restored) return;
    restored = true;
    final generation = ++_generation;
    try {
      final token = await storage.read();
      if (generation != _generation) return;
      api.token = token;
    } catch (_) {
      if (generation != _generation) return;
      status = '无法读取保存的登录信息';
    }
    if (loggedIn) {
      final token = api.token;
      try {
        final info = await api.userInfo();
        if (generation != _generation || token != api.token) return;
        profile = info;
        _profileToken = token;
        status = '';
      } catch (e) {
        if (generation != _generation) return;
        status = '$e';
      }
    }
    notifyListeners();
  }

  Future<void> signIn(
    String account,
    String password, {
    bool withCode = false,
  }) async {
    final generation = ++_generation;
    final data = withCode
        ? await api.loginWithCode(account, password)
        : await api.login(account, password);
    if (generation != _generation) throw const ApiException('账号已切换，请重试');
    final token = '${data['token'] ?? ''}';
    if (token.isEmpty) throw const ApiException('服务器未返回登录信息');
    api.token = token;
    profile = data;
    _profileToken = token;
    status = '';
    try {
      final info = await api.userInfo();
      if (generation != _generation || token != api.token) {
        throw const ApiException('账号已切换，请重试');
      }
      profile = info;
    } catch (e) {
      if (generation != _generation || token != api.token) {
        throw const ApiException('登录已失效，请重新登录');
      }
      status = '$e';
    }
    if (generation != _generation || token != api.token) {
      throw const ApiException('登录已失效，请重新登录');
    }
    if (!loggedIn) throw const ApiException('登录已失效，请重新登录');
    try {
      await storage.write(token);
    } catch (_) {
      status = '登录成功，会话未能保存';
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final generation = ++_generation;
    try {
      if (loggedIn) await api.logout();
    } finally {
      if (generation == _generation) {
        api.token = null;
        api.vipChannels.clear();
        profile = {};
        _profileToken = null;
        status = '';
        try {
          await storage.delete();
        } finally {
          notifyListeners();
        }
      }
    }
  }
}
