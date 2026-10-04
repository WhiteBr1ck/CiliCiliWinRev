import 'dart:io';
import 'dart:ui' as ui;
import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/main.dart';
import 'package:clicli_md3/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../test/ui_test.dart' show CloudUiApi, UiSessionStore;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows account collection and resume with isolated fixtures', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.unmaximize();
    await windowManager.setSize(const Size(1360, 900));
    await windowManager.show();
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    final api = CloudUiApi();
    state.bindAccount(api, storage: UiSessionStore());
    await state.toggleFavorite(const Anime(id: 1, name: '本地收藏样本'));
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await render.toImage(pixelRatio: 1);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'docs/screenshots/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    }

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ClicliApp(state: state, api: api),
        ),
      );
      await tester.pumpAndSettle();
      await state.account!.signIn('fixture', 'fixture');
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('云端收藏样本'), findsOneWidget);
      await capture('account-favorites-0.7.2');
      await tester.tap(find.text('本地'));
      await tester.pumpAndSettle();
      expect(find.text('本地收藏样本'), findsOneWidget);
      expect(find.text('云端收藏样本'), findsNothing);
      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();
      await windowManager.setSize(const Size(760, 580));
      await tester.pumpAndSettle();
      await capture('account-favorites-narrow-0.7.2');
      await tester.tap(find.text('云端收藏样本'));
      await tester.pumpAndSettle();
      expect(find.text('上次看到 第02集 · 01:27'), findsOneWidget);
      expect(find.text('已收藏'), findsOneWidget);
      await capture('account-resume-0.7.2');
      await tester.tap(find.text('已收藏'));
      await tester.pumpAndSettle();
      expect(state.favoritesSync!.items, isEmpty);
      expect(state.favorites.keys, [1]);
      await state.account!.signOut();
      await tester.pumpAndSettle();
      expect(find.text('上次看到 第02集 · 01:27'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      api.dispose();
    }
  });
}
