import 'package:clicli_md3/app_state.dart';
import 'package:clicli_md3/theme.dart';
import 'package:clicli_md3/ui/danmaku_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('accent and danmaku preferences persist with valid limits', () async {
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);
    await state.setAccent('teal');
    await state.setDanmakuStyle(opacity: .6, fontSize: 24, area: .75);
    final restored = AppState(prefs);
    expect(restored.accent, 'teal');
    expect(restored.danmakuOpacity, .6);
    expect(restored.danmakuFontSize, 24);
    expect(restored.danmakuArea, .75);
    await restored.setAccent('unknown');
    expect(restored.accent, 'teal');
  });
  test('all accent themes generate readable primary button colors', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final accent in AppTheme.accents.keys) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.make(brightness, accent: accent);
        final c = theme.colorScheme;
        expect(
          contrast(c.primary, c.onPrimary),
          greaterThanOrEqualTo(4.5),
          reason: '$accent $brightness',
        );
        expect(contrast(c.surface, c.onSurface), greaterThanOrEqualTo(4.5));
        expect(theme.textTheme.bodyMedium!.fontFamily, 'NotoSansSC');
      }
    }
    expect(
      AppTheme.make(Brightness.dark, accent: 'teal').colorScheme.primary,
      isNot(AppTheme.make(Brightness.dark).colorScheme.primary),
    );
  });
  testWidgets(
    'player danmaku composer sends text and preserves failed drafts',
    (tester) async {
      final state = AppState(await SharedPreferences.getInstance());
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.make(Brightness.dark),
          home: Scaffold(
            body: DanmakuBar(
              state: state,
              enabled: true,
              onFocus: (_) {},
              onMenu: (_) {},
              onSend: (text, color, type, size) async {
                sent.add(text);
                if (text == '失败') throw Exception('发送失败');
              },
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('danmaku-input')),
        '测试 f m 弹幕',
      );
      await tester.tap(find.byKey(const Key('danmaku-send')));
      await tester.pumpAndSettle();
      expect(sent, ['测试 f m 弹幕']);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('danmaku-input')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byKey(const Key('danmaku-input')), '失败');
      await tester.tap(find.byKey(const Key('danmaku-send')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('danmaku-input')))
            .controller!
            .text,
        '失败',
      );
      expect(find.text('Exception: 发送失败'), findsOneWidget);
      await tester.tap(find.byTooltip('弹幕显示设置'));
      await tester.pumpAndSettle();
      expect(find.text('透明度'), findsOneWidget);
      expect(find.text('字号'), findsOneWidget);
      expect(find.text('显示区域'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
