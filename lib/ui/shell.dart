import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import '../app_state.dart';
import '../app_version.dart';
import '../services/app_updates.dart';
import '../services/application_exit.dart';
import '../services/windows_updater.dart';
import 'update_settings.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'components.dart';
import 'detail_page.dart';
import 'player_page.dart';
import 'account_dialog.dart';
import 'history_page.dart';
import 'timetable_page.dart';
import 'schedule_lookup_page.dart';
import '../theme.dart';

class AppShell extends StatefulWidget {
  final AppState state;
  final ClicliApi api;
  final AppUpdates? updates;
  const AppShell({
    super.key,
    required this.state,
    required this.api,
    this.updates,
  });
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  int destination = 0, channel = 0, hero = 0, page = 1, total = 0;
  String sort = 'hits', keyword = '', error = '';
  String? year, genre, area;
  bool connecting = true, loading = false, loadingMore = false;
  List<Channel> channels = [];
  List<Anime> banners = [], popular = [], latest = [], results = [];
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final pageFocus = FocusNode(debugLabel: 'shell shortcuts');
  int _generation = 0;
  String? _promptedVersion;
  bool _closing = false;
  static const labels = ['发现', '全部番剧', '我的追番', '收藏', '观看历史', '新番时间表', '设置'];
  static const icons = [
    Icons.explore_outlined,
    Icons.grid_view_rounded,
    Icons.bookmark_border_rounded,
    Icons.favorite_border_rounded,
    Icons.history_rounded,
    Icons.calendar_month_outlined,
    Icons.tune_rounded,
  ];
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (widget.updates != null) {
      widget.updates!.download.shutdown = _closeForUpdate;
    }
    widget.state.bindAccount(widget.api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) pageFocus.requestFocus();
    });
    unawaited(connect());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startupUpdate());
    });
  }

  Future<void> _startupUpdate() async {
    final updates = widget.updates;
    if (updates == null) return;
    await updates.check(startup: true);
    _offerUpdate();
  }

  void _offerUpdate() {
    final release = widget.updates?.release;
    if (!mounted ||
        release == null ||
        _promptedVersion == release.version ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _promptedVersion = release.version;
    unawaited(showUpdateDialog(context, widget.updates!));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    if (widget.updates != null) widget.updates!.download.shutdown = null;
    search.dispose();
    searchFocus.dispose();
    pageFocus.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    // Give immediate feedback while local writes and native cleanup finish.
    await windowManager.hide();
    try {
      widget.state.historySync?.pause();
      await widget.state.flushPlayback?.call();
    } finally {
      widget.updates?.dispose();
      widget.api.dispose();
      await ApplicationExit.finish();
    }
  }

  Future<void> _closeForUpdate() async {
    if (_closing) throw const FormatException('软件正在退出，请重新打开后更新');
    _closing = true;
    try {
      widget.state.historySync?.pause();
      await widget.state.flushPlayback?.call();
    } catch (_) {
      _closing = false;
      widget.state.historySync?.resume();
      widget.state.resumePlayback?.call();
      throw const FormatException('无法保存观看进度，更新已取消。请重试');
    }
    try {
      await WindowsUpdater.commit();
    } catch (_) {
      _closing = false;
      widget.state.historySync?.resume();
      widget.state.resumePlayback?.call();
      throw const FormatException('无法准备安装，更新已取消。请重试');
    }
    await windowManager.hide();
    widget.updates?.dispose();
    widget.api.dispose();
    await ApplicationExit.finish();
  }

  Future<void> connect() async {
    setState(() {
      connecting = true;
      error = '';
    });
    try {
      final host = await widget.api.connect(
        cachedHost: widget.state.preferences.getString('host'),
      );
      await widget.state.preferences.setString('host', host);
      unawaited(widget.state.account!.restore());
      final data = await Future.wait([
        widget.api.channels(),
        widget.api.banners(),
        widget.api.list(),
        widget.api.list(sort: 'addtime'),
      ]);
      if (!mounted) return;
      setState(() {
        channels = data[0] as List<Channel>;
        banners = data[1] as List<Anime>;
        popular = (data[2] as CatalogPage).items;
        latest = (data[3] as CatalogPage).items;
        connecting = false;
      });
      if (destination == 1) await loadCatalog();
    } catch (e) {
      if (mounted) {
        setState(() {
          connecting = false;
          error = '$e';
        });
      }
    }
  }

  void navigate(int value) {
    _generation++;
    setState(() {
      destination = value;
      error = '';
      keyword = '';
      search.clear();
    });
    if (value == 1) unawaited(loadCatalog());
  }

  Future<void> loadCatalog({bool more = false}) async {
    final generation = ++_generation;
    final targetPage = more ? page + 1 : 1;
    setState(() {
      if (more) {
        loadingMore = true;
      } else {
        loading = true;
        results = [];
      }
      error = '';
    });
    try {
      final result = keyword.isNotEmpty
          ? await widget.api.search(keyword, page: targetPage)
          : await widget.api.list(
              channel: channel,
              page: targetPage,
              sort: sort,
              year: year,
              genre: genre,
              area: area,
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        page = targetPage;
        total = result.total;
        results = more
            ? [
                ...results,
                ...result.items.where((a) => !results.any((b) => b.id == a.id)),
              ]
            : result.items;
        loading = false;
        loadingMore = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          loading = false;
          loadingMore = false;
          error = '$e';
        });
      }
    }
  }

  void submitSearch(String value) {
    final key = value.trim();
    if (key.isEmpty) return;
    searchFocus.unfocus();
    setState(() {
      destination = 1;
      keyword = key;
    });
    unawaited(loadCatalog());
  }

  Future<void> open(Anime a, {WatchEntry? resume}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(
          anime: a,
          api: widget.api,
          state: widget.state,
          resume: resume,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
      pageFocus.requestFocus();
      _offerUpdate();
    }
  }

  Future<void> openScheduled(ScheduleEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleLookupPage(
          entry: entry,
          api: widget.api,
          state: widget.state,
        ),
      ),
    );
    if (mounted) {
      pageFocus.requestFocus();
      _offerUpdate();
    }
  }

  Future<void> localVideo() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '视频文件',
          extensions: ['mp4', 'mkv', 'webm', 'avi', 'mov', 'm3u8'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          anime: Anime(id: -1, name: file.name),
          api: widget.api,
          state: widget.state,
          source: const PlaySource('local', '本地文件', ['本地视频']),
          episode: '本地视频',
          directUrl: file.path,
        ),
      ),
    );
    if (mounted) {
      pageFocus.requestFocus();
      _offerUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            searchFocus.requestFocus(),
      },
      child: Focus(
        focusNode: pageFocus,
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final expanded = constraints.maxWidth >= 1120;
              return Row(
                children: [
                  SizedBox(
                    width: expanded ? 212 : 92,
                    child: ColoredBox(
                      color: c.surfaceContainerLow,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 94,
                            child: DragToMoveArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/logo.png',
                                      width: 42,
                                      height: 42,
                                    ),
                                    if (expanded) ...[
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'CiliCiliWinRev',
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: c.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                for (int i = 0; i < 6; i++)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      expanded ? 14 : 10,
                                      3,
                                      expanded ? 14 : 10,
                                      3,
                                    ),
                                    child: _navItem(i, expanded),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(expanded ? 14 : 10),
                            child: _navItem(6, expanded),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: expanded ? 14 : 0,
                              ),
                              leading: const Icon(
                                Icons.account_circle_outlined,
                              ),
                              title: expanded
                                  ? Text(
                                      widget.state.account!.loggedIn
                                          ? widget.state.account!.name
                                          : '登录 / 注册',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    )
                                  : null,
                              onTap: () => showAccountDialog(
                                context,
                                widget.state.account!,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 76,
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DragToMoveArea(
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
                                  child: TextField(
                                    key: const Key('search'),
                                    controller: search,
                                    focusNode: searchFocus,
                                    onSubmitted: submitSearch,
                                    decoration: InputDecoration(
                                      hintText: '搜索番剧、电影…',
                                      labelText: '搜索',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.never,
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                        size: 21,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: '搜索（Ctrl+K）',
                                        onPressed: () =>
                                            submitSearch(search.text),
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                tooltip: '切换深色 / 浅色',
                                onPressed: () => widget.state.setTheme(
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? ThemeMode.light
                                      : ThemeMode.dark,
                                ),
                                icon: Icon(
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const WindowControls(),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                        Expanded(child: _body()),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, bool expanded) {
    final selected = destination == index, c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: labels[index],
      child: Tooltip(
        message: labels[index],
        child: Material(
          color: selected ? c.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(expanded ? 16 : 20),
          child: InkWell(
            onTap: () => navigate(index),
            borderRadius: BorderRadius.circular(expanded ? 16 : 20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
              child: expanded
                  ? Row(
                      children: [
                        Icon(
                          icons[index],
                          size: 21,
                          color: selected
                              ? c.onPrimaryContainer
                              : c.onSurfaceVariant,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          labels[index],
                          style: TextStyle(
                            color: selected
                                ? c.onPrimaryContainer
                                : c.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (index == 2 &&
                            widget.state.following.isNotEmpty) ...[
                          const Spacer(),
                          Text(
                            '${widget.state.following.length}',
                            style: TextStyle(
                              color: c.onPrimaryContainer,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      children: [
                        Icon(
                          icons[index],
                          size: 22,
                          color: selected
                              ? c.onPrimaryContainer
                              : c.onSurfaceVariant,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 10,
                            color: selected
                                ? c.onPrimaryContainer
                                : c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (destination == 6) return _settings();
    if (destination == 5) {
      return TimetablePage(api: widget.api, onOpen: openScheduled);
    }
    if (destination == 4) {
      return HistoryPage(
        state: widget.state,
        api: widget.api,
        onOpen: (e) => open(e.anime, resume: e),
      );
    }
    if (destination >= 2) return _library();
    if (connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 22),
            Text('正在连接片库…'),
          ],
        ),
      );
    }
    if (error.isNotEmpty && (destination == 0 || results.isEmpty)) {
      return ErrorView(message: error, onRetry: connect);
    }
    return destination == 0 ? _home() : _catalog();
  }

  Widget _home() => ListView(
    padding: const EdgeInsets.fromLTRB(30, 10, 30, 32),
    children: [
      if (banners.isNotEmpty) ...[_hero(), const SizedBox(height: 20)],
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.apps_rounded, size: 16),
            label: const Text('全部番剧'),
            onPressed: () {
              channel = 0;
              year = null;
              genre = null;
              area = null;
              navigate(1);
            },
          ),
          ...channels.map(
            (ch) => ActionChip(
              label: Text(ch.name),
              onPressed: () {
                channel = ch.id;
                year = null;
                genre = null;
                area = null;
                navigate(1);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 32),
      if (widget.state.recent.isNotEmpty) ...[
        SectionTitle('继续观看', action: '观看历史', onAction: () => navigate(4)),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.state.recent.take(5).length,
            separatorBuilder: (_, i) => const SizedBox(width: 14),
            itemBuilder: (_, i) => SizedBox(
              width: 320,
              child: _historyCard(widget.state.recent[i], compact: true),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
      SectionTitle(
        '人气精选',
        action: '查看全部',
        onAction: () {
          sort = 'hits';
          channel = 0;
          navigate(1);
        },
      ),
      _grid(popular.take(12).toList()),
      const SizedBox(height: 34),
      SectionTitle(
        '最近上架',
        action: '查看全部',
        onAction: () {
          sort = 'addtime';
          channel = 0;
          navigate(1);
        },
      ),
      _grid(latest.take(12).toList()),
    ],
  );
  Widget _hero() {
    final a = banners[hero % banners.length];
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 760;
        return Container(
          height: narrow ? 320 : 350,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Theme.of(context).colorScheme.surfaceContainer,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(a.backdrop.isEmpty ? a.image : a.backdrop),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFA19151F),
                      Color(0xE619151F),
                      Color(0x7319151F),
                      Color(0x1A19151F),
                    ],
                    stops: [0, .3, .6, 1],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(narrow ? 24 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3C3153),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '编辑推荐',
                        style: TextStyle(
                          color: Color(0xFFE9DEFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: box.maxWidth * (narrow ? 0.8 : 0.52),
                      ),
                      child: Text(
                        a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: narrow ? 25 : 32,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF7F2FA),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      a.status,
                      style: const TextStyle(
                        color: Color(0xFFD5CFE0),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 490),
                      child: Text(
                        a.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD5CFE0),
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => open(a),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('开始观看'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFECE6F0),
                            side: const BorderSide(color: Color(0xFF91899E)),
                          ),
                          onPressed: () =>
                              widget.state.toggleFavorite(a, follow: true),
                          icon: Icon(
                            widget.state.following.containsKey(a.id)
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_add_outlined,
                            size: 19,
                          ),
                          label: Text(
                            widget.state.following.containsKey(a.id)
                                ? '已追番'
                                : '追番',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 22,
                bottom: 22,
                child: Row(
                  children: [
                    for (int i = 0; i < banners.length; i++)
                      Tooltip(
                        message: banners[i].name,
                        child: InkWell(
                          onTap: () => setState(() => hero = i),
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            width: 28,
                            height: 40,
                            child: Center(
                              child: Container(
                                width: hero == i ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: hero == i
                                      ? const Color(0xFFCDBDFF)
                                      : Colors.white54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: '下一部推荐',
                      onPressed: () =>
                          setState(() => hero = (hero + 1) % banners.length),
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grid(List<Anime> items) => LayoutBuilder(
    builder: (context, box) {
      final count = (box.maxWidth / 175).floor().clamp(2, 7);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: 18,
          mainAxisSpacing: 22,
          childAspectRatio: .62,
        ),
        itemBuilder: (_, i) => AnimeCard(
          anime: items[i],
          onTap: () => open(items[i]),
          saved: widget.state.following.containsKey(items[i].id),
          favorite:
              destination != 2 &&
              widget.state.favorites.containsKey(items[i].id),
        ),
      );
    },
  );
  Widget _catalog() {
    final selected = channels.where((ch) => ch.id == channel).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 32),
      children: [
        if (keyword.isNotEmpty) SectionTitle('“$keyword”的搜索结果'),
        if (keyword.isEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: channel == 0,
                onSelected: (_) {
                  setState(() {
                    channel = 0;
                    genre = null;
                    year = null;
                    area = null;
                  });
                  unawaited(loadCatalog());
                },
              ),
              ...channels.map(
                (ch) => ChoiceChip(
                  label: Text(ch.name),
                  selected: channel == ch.id,
                  onSelected: (_) {
                    setState(() {
                      channel = ch.id;
                      genre = null;
                      year = null;
                      area = null;
                    });
                    unawaited(loadCatalog());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _filter(
                '排序',
                sort,
                {'hits': '热度最高', 'addtime': '最近上架', 'gold': '评分最高'},
                (s) {
                  sort = s!;
                  unawaited(loadCatalog());
                },
              ),
              if (selected != null) ...[
                _filter(
                  '类型',
                  genre,
                  {'': '全部类型', for (final s in selected.genres) s: s},
                  (s) {
                    genre = s;
                    unawaited(loadCatalog());
                  },
                ),
                _filter(
                  '年份',
                  year,
                  {'': '全部年份', for (final s in selected.years) s: s},
                  (s) {
                    year = s;
                    unawaited(loadCatalog());
                  },
                ),
                _filter(
                  '地区',
                  area,
                  {'': '全部地区', for (final s in selected.areas) s: s},
                  (s) {
                    area = s;
                    unawaited(loadCatalog());
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
        ],
        if (loading)
          const Padding(
            padding: EdgeInsets.all(80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (results.isEmpty)
          const EmptyView(icon: Icons.search_off_rounded, title: '没有找到匹配的作品')
        else
          _grid(results),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (results.isNotEmpty && results.length < total)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: loadingMore ? null : () => loadCatalog(more: true),
                icon: loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(loadingMore ? '正在加载…' : '加载更多'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filter(
    String label,
    String? value,
    Map<String, String> values,
    void Function(String?) change,
  ) => SizedBox(
    width: 145,
    child: AppMenu<String>(
      label: label,
      value: value ?? '',
      items: values,
      onSelected: (s) {
        setState(() => change(s == '' ? null : s));
      },
    ),
  );
  Widget _library() {
    final items =
        (destination == 2 ? widget.state.following : widget.state.favorites)
            .values
            .toList()
            .reversed
            .toList();
    if (items.isEmpty) {
      return EmptyView(
        icon: destination == 2
            ? Icons.bookmark_border_rounded
            : Icons.favorite_border_rounded,
        title: destination == 2 ? '暂无追番' : '暂无收藏',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 30),
      children: [SectionTitle(labels[destination]), _grid(items)],
    );
  }

  Widget _historyCard(WatchEntry entry, {bool compact = false}) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => open(entry.anime, resume: entry),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: compact ? 64 : 72,
                  height: compact ? 88 : 96,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.anime.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${entry.episode} · ${formatTime(entry.position)}${entry.duration > 0 ? ' / ${formatTime(entry.duration)}' : ''}',
                      style: TextStyle(color: c.onSurfaceVariant, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: entry.progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 20),
                FilledButton.tonalIcon(
                  onPressed: () => open(entry.anime, resume: entry),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('继续观看'),
                ),
                IconButton(
                  tooltip: '移除此记录',
                  onPressed: () => widget.state.removeWatch(entry.anime.id),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _settings() {
    final c = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 30),
      children: [
        _settingsCard(
          '外观',
          Icons.palette_outlined,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      selected: widget.state.themeMode == mode,
                      label: Text(
                        {
                          'system': '跟随系统',
                          'light': '浅色',
                          'dark': '深色',
                        }[mode.name]!,
                      ),
                      onSelected: (_) => widget.state.setTheme(mode),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('强调色'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final entry in AppTheme.accents.entries)
                        ChoiceChip(
                          key: Key('accent-${entry.key}'),
                          selected: widget.state.accent == entry.key,
                          avatar: CircleAvatar(
                            backgroundColor: entry.value.color,
                            radius: 9,
                          ),
                          label: Text(entry.value.name),
                          onSelected: (_) => widget.state.setAccent(entry.key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _settingsCard(
          '播放',
          Icons.play_circle_outline_rounded,
          children: [
            SwitchListTile(
              title: const Text('自动播放下一集'),
              value: widget.state.autoNext,
              onChanged: widget.state.setAutoNext,
            ),
            SwitchListTile(
              title: const Text('默认显示弹幕'),
              value: widget.state.showDanmaku,
              onChanged: widget.state.setDanmaku,
            ),
            ListTile(
              title: const Text('打开本地视频'),
              trailing: const Icon(Icons.folder_open_outlined),
              onTap: localVideo,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _settingsCard(
          '连接与数据',
          Icons.storage_outlined,
          children: [
            ListTile(
              title: const Text('片库连接'),
              subtitle: Text(
                connecting
                    ? '正在连接…'
                    : widget.api.host != null
                    ? '已连接 CLICLI 片库'
                    : '尚未连接',
              ),
              trailing: OutlinedButton(
                onPressed: connecting ? null : connect,
                child: const Text('重新连接'),
              ),
            ),
            ListTile(
              title: const Text('清空本地历史'),
              trailing: TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('清空观看历史？'),
                      content: const Text('这台电脑上的播放记录将被删除，收藏和追番会保留。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('清空历史'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await widget.state.clearHistory();
                },
                child: Text('清空', style: TextStyle(color: c.error)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (widget.updates != null) ...[
          _settingsCard(
            '更新',
            Icons.system_update_alt_rounded,
            children: [UpdateSettings(updates: widget.updates!)],
          ),
          const SizedBox(height: 20),
        ],
        _settingsCard(
          '关于 CiliCiliWinRev',
          Icons.info_outline_rounded,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'CiliCiliWinRev\n$appVersion',
                style: TextStyle(height: 1.9, fontSize: 13),
              ),
            ),
            ListTile(
              title: const Text('CLICLI 官网'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => launchUrl(
                Uri.parse('https://clicli.blog/'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingsCard(
    String title,
    IconData icon, {
    required List<Widget> children,
  }) {
    final c = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(icon, color: c.primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
