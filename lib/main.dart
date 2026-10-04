import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'app_state.dart';
import 'services/app_updates.dart';
import 'services/clicli_api.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1360, 900),
        minimumSize: Size(760, 580),
        center: true,
        title: 'CiliCiliWinRev',
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  if (Platform.isWindows) {
    final directory = await getApplicationSupportDirectory();
    final target = File('${directory.path}/shared_preferences.json');
    final legacy = File(
      '${directory.parent.path}/CLICLI Material 3/shared_preferences.json',
    );
    if (!await target.exists() && await legacy.exists()) {
      await directory.create(recursive: true);
      await legacy.copy(target.path);
    }
  }
  final state = AppState(await SharedPreferences.getInstance());
  final api = ClicliApi();
  await api.loadProtocol();
  runApp(
    ClicliApp(state: state, api: api, updates: AppUpdates(state.preferences)),
  );
}

class ClicliApp extends StatelessWidget {
  final AppState state;
  final ClicliApi api;
  final AppUpdates? updates;
  const ClicliApp({
    super.key,
    required this.state,
    required this.api,
    this.updates,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CiliCiliWinRev',
      theme: AppTheme.make(Brightness.light, accent: state.accent),
      darkTheme: AppTheme.make(Brightness.dark, accent: state.accent),
      themeAnimationDuration: Duration.zero,
      themeMode: state.themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AppShell(state: state, api: api, updates: updates),
    ),
  );
}
