import 'package:flutter/foundation.dart';
import 'clicli_api.dart';
import 'session_store.dart';

class AccountSession extends ChangeNotifier {
  final ClicliApi api;
  final SessionStore storage;
  Map<String, dynamic> profile = {};
  bool restored = false;
  String status = '';
  AccountSession(this.api, {this.storage = const WindowsSessionStore()}) {
    api.onSessionExpired = () {
      profile = {};
      status = '登录已失效';
      notifyListeners();
      storage.delete().catchError((_) {});
    };
  }
  bool get loggedIn => api.token?.isNotEmpty == true;
  String get name =>
      '${profile['user_name'] ?? profile['uname'] ?? profile['nickname'] ?? '账号'}';
  Future<void> restore() async {
    if (restored) return;
    restored = true;
    try {
      api.token = await storage.read();
    } catch (_) {
      status = '无法读取保存的登录信息';
    }
    if (loggedIn) {
      try {
        profile = await api.userInfo();
        status = '';
      } catch (e) {
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
    final data = withCode
        ? await api.loginWithCode(account, password)
        : await api.login(account, password);
    final token = '${data['token'] ?? ''}';
    if (token.isEmpty) throw const ApiException('服务器未返回登录信息');
    api.token = token;
    profile = data;
    status = '';
    try {
      profile = await api.userInfo();
    } catch (e) {
      status = '$e';
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
    try {
      if (loggedIn) await api.logout();
    } finally {
      api.token = null;
      api.vipChannels.clear();
      profile = {};
      status = '';
      try {
        await storage.delete();
      } finally {
        notifyListeners();
      }
    }
  }
}
