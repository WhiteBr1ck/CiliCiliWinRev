import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'components.dart';
import 'player_page.dart';

class DetailPage extends StatefulWidget {
  final Anime anime;
  final ClicliApi api;
  final AppState state;
  final WatchEntry? resume;
  const DetailPage({
    super.key,
    required this.anime,
    required this.api,
    required this.state,
    this.resume,
  });
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final pageFocus = FocusNode(debugLabel: 'detail shortcuts');
  Anime? detail;
  String error = '';
  int source = 0;
  bool expanded = false;
  int generation = 0;
  String? loadedToken;
  String? detailToken, openedToken;
  bool played = false;
  String? playedToken;
  WatchEntry? get lastWatch {
    final a = detail ?? widget.anime;
    if (!played && widget.resume != null && openedToken == widget.api.token) {
      return widget.resume;
    }
    final local = widget.state.history[a.id];
    if (played && playedToken == widget.api.token && local != null) {
      return local;
    }
    final loggedIn = widget.state.account?.loggedIn == true;
    final remote = loggedIn && detailToken == widget.api.token
        ? detail?.accountResume?.entry(a)
        : null;
    final pending = loggedIn
        ? widget.state.historySync?.pendingFor(a.id)
        : null;
    if (pending != null) return pending;
    if (remote == null) return local;
    return remote;
  }

  @override
  void initState() {
    super.initState();
    openedToken = widget.api.token;
    widget.state.addListener(stateChanged);
    unawaited(load());
  }

  void stateChanged() {
    if (!mounted) return;
    if (loadedToken != widget.api.token) {
      unawaited(load());
    } else {
      setState(() {});
    }
  }

  Future<void> toggleFavorite(Anime anime, {bool follow = false}) async {
    try {
      await widget.state.toggleFavorite(anime, follow: follow);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(stateChanged);
    pageFocus.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final id = ++generation;
    loadedToken = widget.api.token;
    final token = loadedToken;
    setState(() => error = '');
    try {
      final a = await widget.api.detail(widget.anime.id);
      if (!mounted || id != generation || token != widget.api.token) return;
      setState(() {
        detail = a;
        detailToken = token;
        final last = lastWatch;
        final index = a.sources.indexWhere((s) => s.id == last?.source);
        source = index < 0 ? 0 : index;
      });
    } catch (e) {
      if (mounted && id == generation) setState(() => error = '$e');
    }
  }

  Future<void> play(String episode, {int position = 0}) async {
    final a = detail;
    if (a == null || a.sources.isEmpty) return;
    final token = widget.api.token;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          anime: a,
          api: widget.api,
          state: widget.state,
          source: a.sources[source],
          episode: episode,
          start: position,
        ),
      ),
    );
    if (mounted) {
      played = true;
      playedToken = token;
      unawaited(load());
      pageFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme, a = detail ?? widget.anime;
    final last = lastWatch;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        focusNode: pageFocus,
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
                    Expanded(
                      child: DragToMoveArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '作品详情',
                            style: TextStyle(
                              color: c.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const WindowControls(),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
              Expanded(
                child: error.isNotEmpty
                    ? ErrorView(message: error, onRetry: load)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(40, 12, 40, 40),
                        children: [
                          LayoutBuilder(
                            builder: (context, box) {
                              final narrow = box.maxWidth < 900;
                              return Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  color: c.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: SizedBox(
                                        width: narrow ? 160 : 216,
                                        height: narrow ? 235 : 310,
                                        child: PosterImage(
                                          a.image,
                                          title: a.name,
                                          year: a.year,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 30),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            a.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontSize: narrow ? 25 : 32,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.4,
                                                ),
                                          ),
                                          const SizedBox(height: 14),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (a.score != null &&
                                                  a.score! > 0)
                                                _badge(
                                                  '★ ${a.score!.toStringAsFixed(1)}',
                                                ),
                                              for (final s in [
                                                a.year,
                                                a.area,
                                                a.status,
                                              ])
                                                if (s.isNotEmpty) _badge(s),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            a.genres,
                                            style: TextStyle(
                                              color: c.onSurfaceVariant,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (a.director.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              '导演  ${a.director}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: c.onSurfaceVariant,
                                                fontSize: 12,
                                                height: 1.6,
                                              ),
                                            ),
                                          ],
                                          if (a.actors.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              '出演  ${a.actors}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: c.onSurfaceVariant,
                                                fontSize: 12,
                                                height: 1.6,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 24),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: [
                                              FilledButton.icon(
                                                key: const Key('detail-play'),
                                                onPressed:
                                                    detail == null ||
                                                        a.sources.isEmpty
                                                    ? null
                                                    : () {
                                                        final s =
                                                            a.sources[source];
                                                        final resume =
                                                            last != null &&
                                                            last.source ==
                                                                s.id &&
                                                            s.episodes.contains(
                                                              last.episode,
                                                            );
                                                        if (s
                                                            .episodes
                                                            .isNotEmpty) {
                                                          unawaited(
                                                            play(
                                                              resume
                                                                  ? last.episode
                                                                  : s
                                                                        .episodes
                                                                        .first,
                                                              position: resume
                                                                  ? last.position
                                                                  : 0,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                icon: const Icon(
                                                  Icons.play_arrow_rounded,
                                                ),
                                                label: Text(
                                                  last == null
                                                      ? '开始观看'
                                                      : '继续观看',
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed: () => toggleFavorite(
                                                  a,
                                                  follow: true,
                                                ),
                                                icon: Icon(
                                                  widget.state.following
                                                          .containsKey(a.id)
                                                      ? Icons.bookmark_rounded
                                                      : Icons
                                                            .bookmark_add_outlined,
                                                  size: 19,
                                                ),
                                                label: Text(
                                                  widget.state.following
                                                          .containsKey(a.id)
                                                      ? '已追番'
                                                      : '追番',
                                                ),
                                              ),
                                              OutlinedButton.icon(
                                                onPressed:
                                                    widget
                                                            .state
                                                            .accountFavoritesSelected &&
                                                        widget
                                                            .state
                                                            .favoritesSync!
                                                            .busy
                                                    ? null
                                                    : () => toggleFavorite(a),
                                                icon: Icon(
                                                  widget.state.visibleFavorites
                                                          .containsKey(a.id)
                                                      ? Icons.favorite_rounded
                                                      : Icons
                                                            .favorite_border_rounded,
                                                  size: 19,
                                                ),
                                                label: Text(
                                                  widget.state.visibleFavorites
                                                          .containsKey(a.id)
                                                      ? '已收藏'
                                                      : '收藏',
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (last != null) ...[
                                            const SizedBox(height: 14),
                                            Text(
                                              '上次看到 ${last.episode} · ${formatTime(last.position)}',
                                              style: TextStyle(
                                                color: c.onSurfaceVariant,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 32),
                          const SectionTitle('故事简介'),
                          SelectionArea(
                            child: Text(
                              a.description.isEmpty ? '暂无简介。' : a.description,
                              maxLines: expanded ? null : 4,
                              style: TextStyle(
                                color: c.onSurfaceVariant,
                                fontSize: 14,
                                height: 1.9,
                              ),
                            ),
                          ),
                          if (a.description.runes.length > 160)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () =>
                                    setState(() => expanded = !expanded),
                                child: Text(expanded ? '收起简介' : '展开简介'),
                              ),
                            ),
                          const SizedBox(height: 24),
                          const SectionTitle('选集'),
                          if (detail == null)
                            const Center(child: CircularProgressIndicator())
                          else if (a.sources.isNotEmpty) ...[
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                for (int i = 0; i < a.sources.length; i++)
                                  ChoiceChip(
                                    label: Text(
                                      '${a.sources[i].name} · ${a.sources[i].episodes.length} 集',
                                    ),
                                    selected: source == i,
                                    onSelected: (_) =>
                                        setState(() => source = i),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            EpisodePicker(
                              key: ValueKey(a.sources[source].id),
                              source: a.sources[source],
                              selected: last?.source == a.sources[source].id
                                  ? last?.episode
                                  : null,
                              onSelect: (e) => play(e),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: c.onSurfaceVariant, fontSize: 11),
      ),
    );
  }
}

class EpisodePicker extends StatefulWidget {
  final PlaySource source;
  final int? columns;
  final String? selected;
  final void Function(String) onSelect;
  const EpisodePicker({
    super.key,
    required this.source,
    this.columns,
    this.selected,
    required this.onSelect,
  });
  @override
  State<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<EpisodePicker> {
  int group = 0;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    final i = widget.source.episodes.indexOf(widget.selected ?? '');
    group = i < 0 ? 0 : i ~/ 50;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EpisodePicker old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected && search.text.isEmpty) {
      final i = widget.source.episodes.indexOf(widget.selected ?? '');
      if (i >= 0) group = i ~/ 50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.source.episodes;
    final filtered = search.text.isEmpty
        ? episodes.skip(group * 50).take(50).toList()
        : episodes.where((s) => s.contains(search.text.trim())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (episodes.length > 50) ...[
          SizedBox(
            width: 220,
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '查找集数',
                hintText: '例如 108',
                prefixIcon: Icon(Icons.search_rounded, size: 19),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < (episodes.length / 50).ceil(); i++)
                ChoiceChip(
                  label: Text(
                    '${i * 50 + 1} ~ ${((i + 1) * 50).clamp(0, episodes.length)}',
                  ),
                  selected: group == i && search.text.isEmpty,
                  onSelected: (_) => setState(() {
                    group = i;
                    search.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        if (filtered.isEmpty)
          const EmptyView(icon: Icons.search_off_rounded, title: '没有匹配的集数'),
        LayoutBuilder(
          builder: (_, box) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: filtered
                .map(
                  (episode) => SizedBox(
                    width: widget.columns == null
                        ? 96
                        : (box.maxWidth - 10 * (widget.columns! - 1)) /
                              widget.columns!,
                    child: widget.selected == episode
                        ? FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => widget.onSelect(episode),
                            child: Text(
                              episode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          )
                        : OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => widget.onSelect(episode),
                            child: Text(
                              episode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
