import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/account_session.dart';
import '../services/clicli_api.dart';

Future<void> showAccountDialog(BuildContext context, AccountSession account) =>
    showDialog<void>(
      context: context,
      builder: (_) => AccountDialog(account: account),
    );

Future<({String uuid, String dots})?> solveCaptcha(
  BuildContext context,
  Map<String, dynamic> data,
) async {
  final controller = TextEditingController();
  final encoded = '${data['image_base64'] ?? ''}'.split(',').last;
  final result = await showDialog<({String uuid, String dots})>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('验证码'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (encoded.isNotEmpty)
              Image.memory(
                base64Decode(encoded),
                height: 100,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '算式结果'),
              onSubmitted: (s) {
                if (s.trim().isNotEmpty) {
                  Navigator.pop(ctx, (
                    uuid: '${data['uuid'] ?? ''}',
                    dots: s.trim(),
                  ));
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(ctx, (
                uuid: '${data['uuid'] ?? ''}',
                dots: controller.text.trim(),
              ));
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // Keep the controller alive through the dialog's closing animation.
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose),
  );
  return result;
}

class AccountDialog extends StatefulWidget {
  final AccountSession account;
  const AccountDialog({super.key, required this.account});
  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      nickname = TextEditingController(),
      code = TextEditingController();
  bool registering = false,
      codeLogin = false,
      busy = false,
      sending = false,
      reveal = false,
      agreed = false;
  int countdown = 0;
  Timer? timer;
  String error = '';
  @override
  void dispose() {
    for (final c in [email, password, confirm, nickname, code]) {
      c.dispose();
    }
    timer?.cancel();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(() => error = '请输入有效邮箱');
      return;
    }
    setState(() {
      sending = true;
      error = '';
    });
    try {
      final type = registering ? 'Reg' : 'login';
      try {
        await widget.account.api.sendCode(email.text.trim(), type);
      } on ApiException catch (e) {
        if (e.code != 429101 && e.code != 429001) rethrow;
        final data = e.data?['image_base64'] != null
            ? e.data!
            : await widget.account.api.captcha(type);
        if (!mounted) return;
        final answer = await solveCaptcha(context, data);
        if (answer == null) return;
        await widget.account.api.sendCode(
          email.text.trim(),
          type,
          uuid: answer.uuid,
          dots: answer.dots,
        );
      }
      if (!mounted) return;
      setState(() => countdown = 60);
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => countdown--);
        if (countdown == 0) t.cancel();
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (!agreed) {
      setState(() => error = '请先同意用户协议和隐私政策');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (registering) {
        await widget.account.api.register(
          nickname: nickname.text.trim(),
          email: email.text.trim(),
          password: password.text,
          code: code.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          registering = false;
          codeLogin = false;
          error = '注册成功，请登录';
        });
      } else {
        await widget.account.signIn(
          email.text.trim(),
          codeLogin ? code.text.trim() : password.text,
          withCode: codeLogin,
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> terms(String type) async {
    try {
      final data = await widget.account.api.agreement();
      final text = data[type];
      if (text is! String || text.trim().isEmpty) {
        throw const ApiException('协议暂时无法加载');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(type == 'user' ? '用户协议' : '隐私政策'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  String? requiredText(String? s) =>
      s == null || s.trim().isEmpty ? '请填写此项' : null;
  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (account.loggedIn) {
      return AlertDialog(
        title: Text(account.name),
        content: account.status.isEmpty ? null : Text(account.status),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await account.signOut();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() {
                          busy = false;
                          error = '$e';
                        });
                      }
                    }
                  },
            child: const Text('退出登录'),
          ),
        ],
      );
    }
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      title: Row(
        children: [
          Expanded(child: Text(registering ? '注册' : '登录')),
          IconButton(
            tooltip: '关闭',
            onPressed: busy || sending ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!registering) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('密码登录')),
                      ButtonSegment(value: true, label: Text('邮箱验证码')),
                    ],
                    selected: {codeLogin},
                    onSelectionChanged: busy || sending
                        ? null
                        : (s) => setState(() {
                            codeLogin = s.first;
                            error = '';
                          }),
                  ),
                  const SizedBox(height: 20),
                ],
                if (registering) ...[
                  TextFormField(
                    controller: nickname,
                    maxLength: 12,
                    decoration: const InputDecoration(labelText: '昵称（中文，不含数字）'),
                    validator: (s) {
                      if (requiredText(s) != null) return '请输入昵称';
                      if (!RegExp(
                        r'^[\u4e00-\u9fff]{1,12}$',
                      ).hasMatch(s!.trim())) {
                        return '昵称请使用 1 至 12 个汉字，不含字母、数字或符号';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: email,
                  enabled: !busy && !sending,
                  decoration: InputDecoration(
                    labelText: registering || codeLogin ? '邮箱' : '邮箱或手机号',
                  ),
                  validator: (s) {
                    if (requiredText(s) != null) return '请输入账号';
                    if ((registering || codeLogin) &&
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(s!.trim())) {
                      return '请输入有效邮箱';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                if (registering || codeLogin) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: code,
                          decoration: const InputDecoration(labelText: '邮箱验证码'),
                          validator: requiredText,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: busy || sending || countdown > 0
                              ? null
                              : sendCode,
                          child: Text(
                            sending
                                ? '发送中'
                                : countdown > 0
                                ? '${countdown}s'
                                : '发送验证码',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (registering || !codeLogin) ...[
                  TextFormField(
                    controller: password,
                    obscureText: !reveal,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '密码',
                      suffixIcon: IconButton(
                        tooltip: reveal ? '隐藏密码' : '显示密码',
                        onPressed: () => setState(() => reveal = !reveal),
                        icon: Icon(
                          reveal
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    onFieldSubmitted: (_) {
                      if (!busy && !sending) submit();
                    },
                    validator: (s) => registering && (s?.length ?? 0) < 6
                        ? '至少 6 个字符'
                        : requiredText(s),
                  ),
                  const SizedBox(height: 14),
                ],
                if (registering) ...[
                  TextFormField(
                    controller: confirm,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '确认密码'),
                    validator: (s) => s != password.text ? '两次密码不一致' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Checkbox(
                      value: agreed,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => agreed = v!),
                    ),
                    const Text('同意', style: TextStyle(fontSize: 12)),
                    TextButton(
                      onPressed: () => terms('user'),
                      child: const Text('用户协议', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => terms('private'),
                      child: const Text('隐私政策', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy || sending ? null : submit,
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(registering ? '注册' : '登录'),
                  ),
                ),
                TextButton(
                  onPressed: busy || sending
                      ? null
                      : () => setState(() {
                          registering = !registering;
                          error = '';
                          form.currentState?.reset();
                        }),
                  child: Text(registering ? '返回登录' : '注册账号'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
