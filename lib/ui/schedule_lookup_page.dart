import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'components.dart';
import 'detail_page.dart';

class ScheduleLookupPage extends StatefulWidget {
  final ScheduleEntry entry;
  final ClicliApi api;
  final AppState state;
  const ScheduleLookupPage({
    super.key,
    required this.entry,
    required this.api,
    required this.state,
  });
  @override
  State<ScheduleLookupPage> createState() => _ScheduleLookupPageState();
}

class _ScheduleLookupPageState extends State<ScheduleLookupPage> {
  bool loading = true;
  Anime? anime;
  String error = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await widget.api.scheduledAnime(widget.entry);
      if (mounted) setState(() => anime = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (anime != null) {
      return DetailPage(anime: anime!, api: widget.api, state: widget.state);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Expanded(
                      child: DragToMoveArea(child: SizedBox.expand()),
                    ),
                    const WindowControls(),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error.isNotEmpty
                    ? ErrorView(message: error, onRetry: load)
                    : const Center(child: Text('CliCli没有该影片')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
