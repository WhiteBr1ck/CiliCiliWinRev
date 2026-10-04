import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'account_dialog.dart';
import 'components.dart';

class HistoryPage extends StatefulWidget {
  final AppState state;
  final ClicliApi api;
  final void Function(WatchEntry) onOpen;
  const HistoryPage({
    super.key,
    required this.state,
    required this.api,
    required this.onOpen,
  });
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool remote = false, loading = false;
  List<AccountHistory> items = [];
  int page = 0, total = 0, generation = 0;
  String error = '';
  String? loadedToken;
  final durationRequests = <String, Future<void>>{};
  final measuredDurations = <String, int>{};
  @override
  void initState() {
    super.initState();
    remote = widget.state.account?.loggedIn == true;
    loadedToken = widget.api.token;
    widget.state.account?.addListener(sessionChanged);
    if (remote) unawaited(load());
  }

  @override
  void dispose() {
    widget.state.account?.removeListener(sessionChanged);
    super.dispose();
  }

  void sessionChanged() {
    if (!mounted) return;
    if (loadedToken != widget.api.token) {
      loadedToken = widget.api.token;
      remote = widget.state.account!.loggedIn;
      generation++;
      items = [];
      page = 0;
      total = 0;
      error = '';
      measuredDurations.clear();
      durationRequests.clear();
      loading = false;
      if (remote && widget.state.account!.loggedIn) unawaited(load());
    }
    setState(() {});
  }

  Future<void> load({bool more = false}) async {
    if (!widget.state.account!.loggedIn) return;
    final id = ++generation, target = more ? page + 1 : 1;
    loadedToken = widget.api.token;
    durationRequests.clear();
    setState(() {
      loading = true;
      error = '';
    });
    try {
      if (!more) await widget.state.historySync?.flush();
      if (!mounted || id != generation || loadedToken != widget.api.token) {
        return;
      }
      final result = await widget.api.accountHistory(page: target);
      if (mounted && id == generation) {
        setState(() {
          items = more ? [...items, ...result.items] : result.items;
          total = result.total;
          page = target;
        });
        unawaited(fillDurations(items.map((i) => i.entry).toList(), id));
      }
    } catch (e) {
      if (mounted && id == generation) setState(() => error = '$e');
    } finally {
      if (mounted && id == generation) setState(() => loading = false);
    }
  }

  int durationFor(WatchEntry entry) => entry.duration > 0
      ? entry.duration
      : widget.state.knownDuration(entry) > 0
      ? widget.state.knownDuration(entry)
      : measuredDurations[AppState.durationKey(entry)] ?? 0;

  Future<void> fillDurations(List<WatchEntry> entries, int id) async {
    var next = 0;
    Future<void> worker() async {
      while (mounted && id == generation && next < entries.length) {
        final entry = entries[next++];
        final key = AppState.durationKey(entry);
        if (durationFor(entry) > 0) continue;
        await durationRequests.putIfAbsent(key, () async {
          try {
            final value = await widget.api.episodeDuration(entry);
            if (mounted && id == generation && value != null && value > 0) {
              setState(() => measuredDurations[key] = value);
              await widget.state.rememberDuration(entry, value);
            }
          } catch (_) {}
        });
      }
    }

    await Future.wait([worker(), worker()]);
  }

  Future<void> remove(WatchEntry entry) async {
    try {
      if (remote) {
        final token = widget.api.token;
        await widget.state.historySync!.delete(entry.anime.id);
        if (mounted && token == widget.api.token) await load();
      } else {
        await widget.state.removeWatch(entry.anime.id);
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = remote
        ? items.map((i) => i.entry).toList()
        : widget.state.recent;
    entries.sort(
      (a, b) =>
          (b.updated ?? DateTime(1970)).compareTo(a.updated ?? DateTime(1970)),
    );
    final groups = <String, List<WatchEntry>>{};
    for (final entry in entries) {
      final date = entry.updated?.toLocal();
      final key = date == null
          ? '时间未知'
          : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(entry);
    }
    final loggedIn = widget.state.account!.loggedIn;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 12, 30, 20),
          child: Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.computer_outlined),
                    label: Text('本地'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.account_circle_outlined),
                    label: Text('账号'),
                  ),
                ],
                selected: {remote},
                onSelectionChanged: (s) {
                  setState(() {
                    remote = s.first;
                    error = '';
                  });
                  if (remote) load();
                },
              ),
              const Spacer(),
              if (remote)
                IconButton(
                  tooltip: '刷新账号历史',
                  onPressed: loggedIn && !loading ? load : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
        ),
        if (error.isNotEmpty && entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: remote && !loggedIn
              ? Center(
                  child: IconButton.filledTonal(
                    tooltip: '登录账号',
                    iconSize: 40,
                    onPressed: () =>
                        showAccountDialog(context, widget.state.account!),
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                )
              : loading && entries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : error.isNotEmpty && entries.isEmpty
              ? ErrorView(message: error, onRetry: load)
              : entries.isEmpty
              ? const EmptyView(icon: Icons.history_rounded, title: '暂无历史')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
                  children: [
                    for (final group in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _dateLabel(group.key),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                      for (final entry in group.value)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.only(left: 20, bottom: 14),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: _card(entry),
                        ),
                    ],
                    if (remote && entries.length < total)
                      Center(
                        child: TextButton(
                          onPressed: loading ? null : () => load(more: true),
                          child: Text(loading ? '加载中' : '加载更多'),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _dateLabel(String key) {
    final date = DateTime.tryParse(key);
    if (date == null) return key;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(date).inDays;
    return days == 0
        ? '今天 · $key'
        : days == 1
        ? '昨天 · $key'
        : key;
  }

  Widget _card(WatchEntry entry) {
    final c = Theme.of(context).colorScheme;
    final duration = durationFor(entry);
    return Material(
      color: c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => widget.onOpen(entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 90,
                  child: PosterImage(
                    entry.anime.image,
                    title: entry.anime.name,
                    year: entry.anime.year,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.anime.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${entry.episode} · ${formatTime(entry.position)}',
                      style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                    ),
                    if (entry.updated != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '观看于 ${entry.updated!.toLocal().hour.toString().padLeft(2, '0')}:${entry.updated!.toLocal().minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (duration > 0 || remote) ...[
                      const SizedBox(height: 12),
                      Tooltip(
                        message: duration > 0
                            ? '${formatTime(entry.position)} / ${formatTime(duration)}'
                            : '已观看 ${formatTime(entry.position)}，暂未取得总时长',
                        child: LinearProgressIndicator(
                          key: ValueKey('history-progress-${entry.anime.id}'),
                          value: duration > 0
                              ? (entry.position / duration).clamp(0, 1)
                              : 0,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '继续观看',
                onPressed: () => widget.onOpen(entry),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: '移除此记录',
                onPressed: () => remove(entry),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
