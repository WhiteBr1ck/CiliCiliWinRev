import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Playable;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'components.dart';
import 'detail_page.dart';
import 'community_panel.dart';
import 'danmaku_overlay.dart';
import '../theme.dart';
import '../services/window_fullscreen.dart';
import 'account_dialog.dart';
import 'danmaku_bar.dart';

class PlayerPage extends StatefulWidget {
  final Anime anime;
  final ClicliApi api;
  final AppState state;
  final PlaySource source;
  final String episode;
  final int start;
  final String? directUrl;
  const PlayerPage({
    super.key,
    required this.anime,
    required this.api,
    required this.state,
    required this.source,
    required this.episode,
    this.start = 0,
    this.directUrl,
  });
  @override
  State<PlayerPage> createState() => PlayerPageState();
}

class PlayerPageState extends State<PlayerPage> {
  late final Player player;
  late final VideoController controller;
  late PlaySource source;
  late String episode;
  late bool danmaku;
  final List<StreamSubscription> subscriptions = [];
  List<Playable> qualities = [];
  int quality = 0,
      requestId = 0,
      position = 0,
      duration = 0,
      _danmakuBlock = -1;
  bool resolving = true,
      playing = false,
      buffering = false,
      fullscreen = false,
      pinned = false,
      panel = true,
      muted = false;
  String error = '', danmakuError = '';
  double rate = 1, volume = 80, precisePosition = 0;
  double? seekPreview;
  bool controlsVisible = true, menuOpen = false, controlsHovered = false;
  bool editorFocused = false, fullscreenBusy = false;
  List<DanmakuEntry> comments = [];
  Timer? saveTimer, hideTimer, errorTimer;
  String get historyError => widget.state.historySync?.error ?? '';
  bool _shuttingDown = false;
  Future<void>? _closing, _release;
  void _historyChanged() {
    if (mounted && !_shuttingDown) setState(() {});
  }

  final focus = FocusNode();
  final danmakuComposerKey = GlobalKey();
  int get nextIndex => source.episodes.indexOf(episode) + 1;
  bool get hasNext => nextIndex > 0 && nextIndex < source.episodes.length;
  @override
  void initState() {
    super.initState();
    source = widget.source;
    episode = widget.episode;
    danmaku = widget.state.showDanmaku;
    volume = widget.state.volume;
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'CiliCiliWinRev',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    controller = VideoController(player);
    widget.state.flushPlayback = shutdown;
    widget.state.resumePlayback = resumeAfterFailedShutdown;
    widget.state.historySync?.addListener(_historyChanged);
    subscriptions.addAll([
      player.stream.position.listen((p) {
        if (mounted) {
          setState(() {
            position = p.inSeconds;
            precisePosition = p.inMicroseconds / 1000000;
          });
          if (danmaku && widget.directUrl == null) {
            unawaited(loadDanmaku(p.inSeconds));
          }
        }
      }),
      player.stream.duration.listen((p) {
        if (mounted) {
          setState(() => duration = p.inSeconds);
          if (p.inSeconds > 0 && danmaku && widget.directUrl == null) {
            unawaited(loadDanmaku(position));
          }
        }
      }),
      player.stream.playing.listen((v) {
        if (mounted) {
          setState(() {
            playing = v;
            if (!v) controlsVisible = true;
          });
          if (v) revealControls();
        }
      }),
      player.stream.buffering.listen((v) {
        if (mounted) setState(() => buffering = v);
      }),
      player.stream.error.listen((e) {
        if (mounted && e.isNotEmpty) {
          final failedRequest = requestId, at = precisePosition;
          errorTimer?.cancel();
          errorTimer = Timer(const Duration(seconds: 5), () {
            if (mounted &&
                requestId == failedRequest &&
                precisePosition <= at &&
                !resolving &&
                (buffering || duration == 0)) {
              setState(() {
                error = '视频加载失败，请重试或切换播放源';
                controlsVisible = true;
              });
            }
          });
        }
      }),
      player.stream.completed.listen((v) {
        if (v && mounted && widget.state.autoNext && hasNext && !resolving) {
          unawaited(switchEpisode(source.episodes[nextIndex]));
        }
      }),
    ]);
    saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(save()),
    );
    unawaited(player.setVolume(volume));
    unawaited(load(start: widget.start));
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    hideTimer?.cancel();
    errorTimer?.cancel();
    if (!_shuttingDown) unawaited(save(notify: false));
    widget.state.flushPlayback = null;
    widget.state.resumePlayback = null;
    widget.state.historySync?.removeListener(_historyChanged);
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    focus.dispose();
    unawaited(_releasePlayer());
    if (fullscreen) unawaited(WindowFullscreen.set(false));
    if (pinned) unawaited(windowManager.setAlwaysOnTop(false));
    super.dispose();
  }

  Future<void> save({bool notify = true, bool transmit = true}) async {
    if (widget.anime.id < 0 || position <= 0 || resolving) return;
    final entry = WatchEntry(
      widget.anime,
      source.id,
      episode,
      position,
      duration,
      DateTime.now(),
    );
    await widget.state.saveWatch(entry, notify: notify);
    await widget.state.historySync?.enqueue(entry, transmit: transmit);
  }

  Future<void> shutdown() => _closing ??= _shutdown();
  Future<void> _shutdown() async {
    _shuttingDown = true;
    saveTimer?.cancel();
    hideTimer?.cancel();
    errorTimer?.cancel();
    widget.state.historySync?.pause();
    try {
      await save(notify: false, transmit: false);
    } catch (_) {
      resumeAfterFailedShutdown();
      rethrow;
    }
  }

  void resumeAfterFailedShutdown() {
    _shuttingDown = false;
    _closing = null;
    widget.state.historySync?.resume();
    if (mounted) {
      saveTimer?.cancel();
      saveTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(save()),
      );
      revealControls();
    }
  }

  Future<void> _releasePlayer() => _release ??= () async {
    await Future.wait(subscriptions.map((s) => s.cancel()));
    await player.dispose();
  }();

  Future<void> load({int start = 0}) async {
    final id = ++requestId;
    setState(() {
      resolving = true;
      error = '';
      comments = [];
      danmakuError = '';
      position = 0;
      precisePosition = 0;
      seekPreview = null;
      controlsVisible = true;
      duration = 0;
      _danmakuBlock = -1;
    });
    await player.stop();
    try {
      final list = widget.directUrl != null
          ? [Playable('本地', widget.directUrl!)]
          : await widget.api.resolve(
              widget.anime.id,
              source.id,
              episode,
              channel: widget.anime.channel,
            );
      if (!mounted || id != requestId) return;
      setState(() {
        qualities = list;
        quality = 0;
      });
      await player.open(
        Media(
          list.first.url,
          httpHeaders: list.first.headers,
          start: Duration(seconds: start),
        ),
      );
      if (!mounted || id != requestId) return;
      setState(() => resolving = false);
      focus.requestFocus();
    } catch (e) {
      if (mounted && id == requestId) {
        setState(() {
          resolving = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> switchEpisode(String value) async {
    if (resolving) return;
    await save();
    if (!mounted) return;
    setState(() => episode = value);
    await load();
  }

  Future<void> switchQuality(int index) async {
    if (index == quality || resolving) return;
    final time = player.state.position;
    final selected = qualities[index];
    setState(() {
      quality = index;
      error = '';
      resolving = true;
    });
    try {
      await player.open(
        Media(selected.url, httpHeaders: selected.headers, start: time),
      );
    } catch (_) {
      if (mounted) setState(() => error = '画质切换失败，请重试或选择其他画质');
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Future<void> loadDanmaku(int seconds) async {
    if (duration <= 0) return;
    final block = duration;
    if (block == _danmakuBlock) return;
    _danmakuBlock = block;
    final id = requestId;
    try {
      final batches = await Future.wait([
        for (int start = 0; start <= duration; start += 600)
          widget.api.danmaku(
            widget.anime.id,
            source.id,
            episode,
            start,
            end: (start + 600).clamp(0, duration + 1),
          ),
      ]);
      final unique = <int, DanmakuEntry>{};
      for (final j in batches.expand((list) => list)) {
        final entry = DanmakuEntry.parse(j);
        if (entry != null) unique[entry.id] = entry;
      }
      if (!mounted || requestId != id || _danmakuBlock != block) return;
      setState(() {
        comments = unique.values.toList()
          ..sort((a, b) => a.time.compareTo(b.time));
        danmakuError = '';
      });
    } catch (e) {
      if (mounted && requestId == id) {
        setState(() => danmakuError = '弹幕暂时无法加载');
      }
    }
  }

  Future<void> toggleFullscreen() async {
    if (fullscreenBusy) return;
    fullscreenBusy = true;
    final next = !fullscreen;
    try {
      await WindowFullscreen.set(next);
      if (mounted) {
        setState(() => fullscreen = next);
        revealControls();
      }
    } finally {
      fullscreenBusy = false;
    }
  }

  Future<void> sendDanmaku(
    String text,
    int color,
    int type,
    String size,
  ) async {
    final timestamp = precisePosition,
        current = requestId,
        currentSource = source.id,
        currentEpisode = episode;
    final account = widget.state.account!;
    if (!account.loggedIn) {
      await showAccountDialog(context, account);
      if (!mounted || !account.loggedIn) throw const ApiException('登录后可发送弹幕');
    }
    Future<void> send({String uuid = '', String dots = ''}) =>
        widget.api.sendDanmaku(
          widget.anime.id,
          currentSource,
          currentEpisode,
          timestamp,
          text,
          color: color,
          type: type,
          size: size,
          uuid: uuid,
          dots: dots,
        );
    try {
      await send();
    } on ApiException catch (e) {
      if (![429101, 429001].contains(e.code)) rethrow;
      final challenge = e.data?['image_base64'] != null
          ? e.data!
          : await widget.api.danmakuCaptcha();
      if (!mounted) return;
      final answer = await solveCaptcha(context, challenge);
      if (answer == null) throw const ApiException('发送已取消');
      await send(uuid: answer.uuid, dots: answer.dots);
    }
    if (mounted && requestId == current) {
      setState(
        () => comments.add(
          DanmakuEntry(
            -DateTime.now().microsecondsSinceEpoch,
            timestamp,
            text,
            color,
            type: type,
            size: size,
          ),
        ),
      );
    }
  }

  Future<void> exit() async {
    if (fullscreen) {
      await toggleFullscreen();
      return;
    }
    await save();
    if (mounted) Navigator.pop(context);
  }

  void seek(int delta) => unawaited(
    player.seek(
      Duration(
        seconds: (position + delta).clamp(
          0,
          duration > 0 ? duration : position + delta.abs(),
        ),
      ),
    ),
  );
  void setVolume(double v) {
    setState(() {
      volume = v.clamp(0, 100);
      muted = volume == 0;
    });
    unawaited(player.setVolume(volume));
    unawaited(widget.state.setVolume(volume));
  }

  void revealControls() {
    if (!mounted) return;
    if (!controlsVisible) setState(() => controlsVisible = true);
    hideTimer?.cancel();
    hideTimer = Timer(Duration(seconds: fullscreen ? 2 : 3), () {
      if (mounted &&
          playing &&
          !menuOpen &&
          seekPreview == null &&
          !editorFocused &&
          !resolving &&
          error.isEmpty) {
        setState(() => controlsVisible = false);
      }
    });
  }

  void toggleDanmaku() {
    setState(() => danmaku = !danmaku);
    if (danmaku) {
      _danmakuBlock = -1;
      unawaited(loadDanmaku(position));
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerTheme = AppTheme.make(
      Brightness.dark,
      accent: widget.state.accent,
    );
    return CallbackShortcuts(
      bindings: editorFocused
          ? {}
          : {
              const SingleActivator(LogicalKeyboardKey.space): () {
                revealControls();
                player.playOrPause();
              },
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                revealControls();
                seek(-10);
              },
              const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                revealControls();
                seek(10);
              },
              const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                revealControls();
                setVolume(volume + 5);
              },
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                revealControls();
                setVolume(volume - 5);
              },
              const SingleActivator(LogicalKeyboardKey.keyF): toggleFullscreen,
              const SingleActivator(LogicalKeyboardKey.escape): exit,
              const SingleActivator(LogicalKeyboardKey.keyM): () {
                revealControls();
                setState(() => muted = !muted);
                player.setVolume(muted ? 0 : volume);
              },
            },
      child: Focus(
        autofocus: true,
        focusNode: focus,
        onFocusChange: (focused) {
          if (focused) revealControls();
        },
        child: Scaffold(
          body: Column(
            children: [
              if (!fullscreen)
                SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: '返回详情',
                        onPressed: exit,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: DragToMoveArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              widget.anime.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (historyError.isNotEmpty)
                        Tooltip(
                          message: '账号历史同步失败：$historyError',
                          child: const Icon(Icons.cloud_off_outlined, size: 18),
                        ),
                      IconButton(
                        tooltip: pinned ? '取消置顶' : '窗口置顶',
                        icon: Icon(
                          pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 19,
                        ),
                        onPressed: () async {
                          await windowManager.setAlwaysOnTop(!pinned);
                          if (mounted) setState(() => pinned = !pinned);
                        },
                      ),
                      const WindowControls(),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final showPanel =
                        panel &&
                        !fullscreen &&
                        box.maxWidth >= 960 &&
                        widget.directUrl == null;
                    return Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              fullscreen ? 0 : 20,
                              fullscreen ? 0 : 8,
                              fullscreen
                                  ? 0
                                  : showPanel
                                  ? 12
                                  : 20,
                              fullscreen ? 0 : 20,
                            ),
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: fullscreen
                                    ? box.maxWidth / box.maxHeight
                                    : 16 / 9,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    fullscreen ? 0 : 20,
                                  ),
                                  child: MouseRegion(
                                    key: const Key('video-mouse-region'),
                                    cursor: controlsVisible || !playing
                                        ? SystemMouseCursors.basic
                                        : SystemMouseCursors.none,
                                    onHover: (_) => revealControls(),
                                    onEnter: (_) => revealControls(),
                                    child: LayoutBuilder(
                                      builder: (context, videoBox) => ColoredBox(
                                        color: Colors.black,
                                        child: Stack(
                                          key: const Key('video-frame'),
                                          fit: StackFit.expand,
                                          children: [
                                            Video(
                                              controller: controller,
                                              controls: NoVideoControls,
                                              wakelock: true,
                                              pauseUponEnteringBackgroundMode:
                                                  false,
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                focus.requestFocus();
                                                revealControls();
                                                player.playOrPause();
                                              },
                                              onDoubleTap: toggleFullscreen,
                                              behavior:
                                                  HitTestBehavior.translucent,
                                            ),
                                            if (danmaku &&
                                                !resolving &&
                                                error.isEmpty &&
                                                !MediaQuery.of(
                                                  context,
                                                ).disableAnimations)
                                              ListenableBuilder(
                                                listenable: widget.state,
                                                builder: (_, __) =>
                                                    DanmakuOverlay(
                                                      items: comments,
                                                      position: precisePosition,
                                                      playing:
                                                          playing && !buffering,
                                                      rate: rate,
                                                      opacity: widget
                                                          .state
                                                          .danmakuOpacity,
                                                      fontSize: widget
                                                          .state
                                                          .danmakuFontSize,
                                                      area: widget
                                                          .state
                                                          .danmakuArea,
                                                    ),
                                              ),
                                            if ((resolving || buffering) &&
                                                error.isEmpty)
                                              const Center(
                                                child: SizedBox(
                                                  width: 38,
                                                  height: 38,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white70,
                                                        strokeWidth: 3,
                                                      ),
                                                ),
                                              ),
                                            if (error.isNotEmpty)
                                              Theme(
                                                data: playerTheme,
                                                child: ColoredBox(
                                                  color: const Color(
                                                    0xEE141218,
                                                  ),
                                                  child: ErrorView(
                                                    message: error,
                                                    onRetry: () => load(),
                                                  ),
                                                ),
                                              ),
                                            Positioned(
                                              top: 0,
                                              left: 0,
                                              right: 0,
                                              child: IgnorePointer(
                                                ignoring: !controlsVisible,
                                                child: AnimatedOpacity(
                                                  opacity: controlsVisible
                                                      ? 1
                                                      : 0,
                                                  duration: const Duration(
                                                    milliseconds: 160,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          18,
                                                          14,
                                                          18,
                                                          36,
                                                        ),
                                                    decoration:
                                                        const BoxDecoration(
                                                          gradient: LinearGradient(
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                            colors: [
                                                              Colors.black87,
                                                              Colors
                                                                  .transparent,
                                                            ],
                                                          ),
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        if (fullscreen)
                                                          IconButton(
                                                            tooltip: '退出全屏',
                                                            onPressed:
                                                                toggleFullscreen,
                                                            color: Colors.white,
                                                            icon: const Icon(
                                                              Icons
                                                                  .arrow_back_rounded,
                                                            ),
                                                          ),
                                                        Expanded(
                                                          child: Text(
                                                            fullscreen
                                                                ? '${widget.anime.name} · $episode'
                                                                : '$episode · ${source.name}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 12,
                                                                ),
                                                          ),
                                                        ),
                                                        if (widget.directUrl ==
                                                            null)
                                                          IconButton(
                                                            tooltip: showPanel
                                                                ? '收起面板'
                                                                : '选集与评论',
                                                            color: Colors.white,
                                                            icon: const Icon(
                                                              Icons
                                                                  .view_sidebar_outlined,
                                                              size: 20,
                                                            ),
                                                            onPressed: () {
                                                              if (!fullscreen &&
                                                                  box.maxWidth >=
                                                                      960) {
                                                                setState(
                                                                  () => panel =
                                                                      !panel,
                                                                );
                                                              } else {
                                                                showModalBottomSheet<
                                                                  void
                                                                >(
                                                                  context:
                                                                      context,
                                                                  isScrollControlled:
                                                                      true,
                                                                  showDragHandle:
                                                                      true,
                                                                  builder: (_) => SizedBox(
                                                                    height:
                                                                        MediaQuery.sizeOf(
                                                                          context,
                                                                        ).height *
                                                                        .78,
                                                                    child:
                                                                        _episodePanel(),
                                                                  ),
                                                                );
                                                              }
                                                            },
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              bottom: 0,
                                              left: 0,
                                              right: 0,
                                              child: IgnorePointer(
                                                ignoring: !controlsVisible,
                                                child: AnimatedOpacity(
                                                  opacity: controlsVisible
                                                      ? 1
                                                      : 0,
                                                  duration: const Duration(
                                                    milliseconds: 160,
                                                  ),
                                                  child: Theme(
                                                    data: playerTheme.copyWith(
                                                      iconTheme:
                                                          const IconThemeData(
                                                            color: Colors.white,
                                                          ),
                                                      sliderTheme: SliderThemeData(
                                                        activeTrackColor:
                                                            playerTheme
                                                                .colorScheme
                                                                .primary,
                                                        inactiveTrackColor:
                                                            Colors.white24,
                                                        thumbColor: playerTheme
                                                            .colorScheme
                                                            .primary,
                                                        trackHeight: 3,
                                                        thumbShape:
                                                            const RoundSliderThumbShape(
                                                              enabledThumbRadius:
                                                                  6,
                                                            ),
                                                      ),
                                                    ),
                                                    child: MouseRegion(
                                                      onEnter: (_) {
                                                        controlsHovered = true;
                                                        revealControls();
                                                      },
                                                      onExit: (_) {
                                                        controlsHovered = false;
                                                        if (controlsVisible) {
                                                          revealControls();
                                                        }
                                                      },
                                                      child: Container(
                                                        key: const Key(
                                                          'player-controls',
                                                        ),
                                                        padding:
                                                            const EdgeInsets.fromLTRB(
                                                              14,
                                                              44,
                                                              14,
                                                              12,
                                                            ),
                                                        decoration: const BoxDecoration(
                                                          gradient: LinearGradient(
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                            colors: [
                                                              Colors
                                                                  .transparent,
                                                              Colors.black87,
                                                            ],
                                                          ),
                                                        ),
                                                        child: _controls(
                                                          videoBox.maxWidth,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showPanel)
                          SizedBox(width: 340, child: _episodePanel()),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void menuVisibility(bool open) {
    menuOpen = open;
    revealControls();
  }

  Widget _controls(double width) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          key: const Key('seek'),
          label: formatTime((seekPreview ?? position).toInt()),
          value: (seekPreview ?? precisePosition).clamp(
            0,
            duration > 0 ? duration.toDouble() : 1,
          ),
          max: duration > 0 ? duration.toDouble() : 1,
          onChangeStart: duration > 0
              ? (v) {
                  revealControls();
                  setState(() => seekPreview = v);
                }
              : null,
          onChanged: duration > 0
              ? (v) => setState(() => seekPreview = v)
              : null,
          onChangeEnd: duration > 0
              ? (v) {
                  setState(() => seekPreview = null);
                  player.seek(Duration(milliseconds: (v * 1000).round()));
                  revealControls();
                }
              : null,
        ),
        Row(
          children: [
            IconButton(
              key: const Key('play-pause'),
              tooltip: playing ? '暂停（空格）' : '播放（空格）',
              onPressed: resolving
                  ? null
                  : () {
                      revealControls();
                      player.playOrPause();
                    },
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 28,
              ),
            ),
            if (width >= 480)
              IconButton(
                tooltip: '下一集',
                onPressed: hasNext && !resolving
                    ? () => switchEpisode(source.episodes[nextIndex])
                    : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            Text(
              '${formatTime((seekPreview ?? position).toInt())} / ${formatTime(duration)}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (widget.directUrl == null && width >= 850) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Center(
                  child: SizedBox(width: 340, child: _danmakuComposer()),
                ),
              ),
              const SizedBox(width: 8),
            ] else
              const Spacer(),
            if (width >= 1240) ...[
              if (widget.directUrl == null)
                IconButton(
                  tooltip: danmaku ? '关闭弹幕' : '显示弹幕',
                  onPressed: toggleDanmaku,
                  icon: Icon(
                    danmaku
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_outlined,
                    size: 20,
                  ),
                ),
              AppMenu<double>(
                label: '播放速度',
                value: rate,
                onOpen: menuVisibility,
                items: {
                  for (final v in [.5, .75, 1.0, 1.25, 1.5, 2.0]) v: '${v}x',
                },
                onSelected: (v) {
                  setState(() => rate = v);
                  player.setRate(v);
                },
              ),
              const SizedBox(width: 8),
              if (qualities.isNotEmpty)
                AppMenu<int>(
                  label: '画质',
                  value: quality,
                  onOpen: menuVisibility,
                  items: {
                    for (int i = 0; i < qualities.length; i++)
                      i: qualities[i].name,
                  },
                  onSelected: switchQuality,
                ),
            ] else
              MenuAnchor(
                onOpen: () => menuVisibility(true),
                onClose: () => menuVisibility(false),
                style: MenuStyle(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                menuChildren: [
                  if (widget.directUrl == null)
                    MenuItemButton(
                      onPressed: toggleDanmaku,
                      child: Text(danmaku ? '关闭弹幕' : '显示弹幕'),
                    ),
                  SubmenuButton(
                    menuChildren: [
                      for (final v in [.5, .75, 1.0, 1.25, 1.5, 2.0])
                        MenuItemButton(
                          onPressed: () {
                            setState(() => rate = v);
                            player.setRate(v);
                          },
                          leadingIcon: Icon(
                            rate == v ? Icons.check_rounded : null,
                          ),
                          child: Text('${v}x'),
                        ),
                    ],
                    child: const Text('播放速度'),
                  ),
                  if (qualities.isNotEmpty)
                    SubmenuButton(
                      menuChildren: [
                        for (int i = 0; i < qualities.length; i++)
                          MenuItemButton(
                            onPressed: () => switchQuality(i),
                            leadingIcon: Icon(
                              quality == i ? Icons.check_rounded : null,
                            ),
                            child: Text(qualities[i].name),
                          ),
                      ],
                      child: const Text('画质'),
                    ),
                ],
                builder: (context, menu, _) => IconButton(
                  tooltip: '播放设置',
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  icon: const Icon(Icons.tune_rounded, size: 20),
                ),
              ),
            IconButton(
              tooltip: muted ? '取消静音（M）' : '静音（M）',
              onPressed: () {
                setState(() => muted = !muted);
                player.setVolume(muted ? 0 : volume);
              },
              icon: Icon(
                muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                size: 20,
              ),
            ),
            if (width >= 620)
              SizedBox(
                width: width >= 1000 ? 180 : 140,
                child: Slider(
                  key: const Key('volume-slider'),
                  value: muted ? 0 : volume,
                  max: 100,
                  onChanged: setVolume,
                ),
              ),
            IconButton(
              tooltip: fullscreen ? '退出全屏（F）' : '全屏（F）',
              onPressed: toggleFullscreen,
              icon: Icon(
                fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
              ),
            ),
          ],
        ),
        if (widget.directUrl == null && width < 850)
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: width >= 620 ? 380 : width - 28,
              child: _danmakuComposer(),
            ),
          ),
      ],
    );
  }

  Widget _danmakuComposer() => DanmakuBar(
    key: danmakuComposerKey,
    state: widget.state,
    enabled: !resolving && error.isEmpty,
    onSend: sendDanmaku,
    onMenu: menuVisibility,
    onFocus: (v) {
      if (mounted) setState(() => editorFocused = v);
      revealControls();
    },
  );

  Widget _episodePanel() {
    final c = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 8, 16, 20),
        decoration: BoxDecoration(
          color: c.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '选集'),
                Tab(text: '弹幕'),
                Tab(text: '评论'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (widget.anime.sources.length > 1)
                        AppMenu<String>(
                          label: '播放源',
                          value: source.id,
                          items: {
                            for (final s in widget.anime.sources) s.id: s.name,
                          },
                          width: double.infinity,
                          onSelected: resolving
                              ? null
                              : (id) async {
                                  await save();
                                  if (!mounted) return;
                                  setState(
                                    () => source = widget.anime.sources
                                        .firstWhere((s) => s.id == id),
                                  );
                                  if (!source.episodes.contains(episode) &&
                                      source.episodes.isNotEmpty) {
                                    episode = source.episodes.first;
                                  }
                                  await load();
                                },
                        ),
                      const SizedBox(height: 16),
                      EpisodePicker(
                        key: ValueKey(source.id),
                        source: source,
                        columns: 3,
                        selected: episode,
                        onSelect: switchEpisode,
                      ),
                      const SizedBox(height: 16),
                      ListenableBuilder(
                        listenable: widget.state,
                        builder: (_, __) => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            '自动连播',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: widget.state.autoNext,
                          onChanged: widget.state.setAutoNext,
                        ),
                      ),
                    ],
                  ),
                  danmakuError.isNotEmpty
                      ? ErrorView(
                          message: danmakuError,
                          onRetry: () {
                            _danmakuBlock = -1;
                            loadDanmaku(position);
                          },
                        )
                      : comments.isEmpty
                      ? const EmptyView(
                          icon: Icons.subtitles_outlined,
                          title: '暂无弹幕',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: comments.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatTime(comments[i].time.toInt()),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    comments[i].text,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  CommunityPanel(
                    api: widget.api,
                    state: widget.state,
                    videoId: widget.anime.id,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
