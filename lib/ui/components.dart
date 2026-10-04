import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../models.dart';
import '../services/cover_cache.dart';

class PosterImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final String title, year;
  const PosterImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.title = '',
    this.year = '',
  });
  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  late Future<Uint8List?> pending;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    pending = widget.url.isEmpty && widget.title.isEmpty
        ? Future.value(null)
        : CoverCache.load(widget.url, title: widget.title, year: widget.year);
  }

  @override
  void didUpdateWidget(PosterImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url ||
        old.title != widget.title ||
        old.year != widget.year) {
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: c.surfaceContainerHigh,
      child: Center(
        child: Icon(Icons.movie_outlined, size: 40, color: c.onSurfaceVariant),
      ),
    );
    return FutureBuilder<Uint8List?>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          if (snapshot.connectionState != ConnectionState.done ||
              widget.url.isEmpty && widget.title.isEmpty) {
            return placeholder;
          }
          return ColoredBox(
            color: c.surfaceContainerHigh,
            child: Center(
              child: IconButton(
                tooltip: '重试封面',
                onPressed: () => setState(load),
                icon: Icon(
                  Icons.movie_outlined,
                  size: 40,
                  color: c.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          excludeFromSemantics: true,
          errorBuilder: (_, e, s) => placeholder,
          gaplessPlayback: true,
        );
      },
    );
  }
}

class AnimeCard extends StatefulWidget {
  final Anime anime;
  final VoidCallback onTap;
  final bool saved;
  final bool favorite;
  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.saved = false,
    this.favorite = false,
  });
  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.anime, c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: a.name,
      child: Tooltip(
        message: a.name,
        child: MouseRegion(
          onEnter: (_) => setState(() => hover = true),
          onExit: (_) => setState(() => hover = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PosterImage(a.image, title: a.name, year: a.year),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .1),
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                10,
                                30,
                                10,
                                10,
                              ),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xD9000000),
                                  ],
                                ),
                              ),
                              child: Text(
                                a.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          if (widget.saved || widget.favorite)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Tooltip(
                                message: widget.favorite ? '已收藏' : '已追番',
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: c.primaryContainer,
                                  child: Icon(
                                    widget.favorite
                                        ? Icons.favorite_rounded
                                        : Icons.bookmark_rounded,
                                    size: 16,
                                    color: c.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          if (a.score != null && a.score! > 0)
                            Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xCC19151F),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  a.score!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Color(0xFFFFD88B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          if (hover)
                            Center(
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: c.primary,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: c.onPrimary,
                                  size: 30,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 3),
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hover ? c.primary : c.onSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      a.metadata.isEmpty ? '查看详情与选集' : a.metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  const SectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        label: title,
        child: Icon(
          icon,
          size: 56,
          color: c.onSurfaceVariant.withValues(alpha: .5),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: c.surfaceContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: c.error,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onSurfaceVariant, height: 1.7),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

class AppMenu<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onSelected;
  final double? width;
  final ValueChanged<bool>? onOpen;
  const AppMenu({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    this.onSelected,
    this.width,
    this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return MenuAnchor(
      onOpen: () => onOpen?.call(true),
      onClose: () => onOpen?.call(false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        maximumSize: const WidgetStatePropertyAll(Size(320, 340)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      menuChildren: [
        for (final entry in items.entries)
          MenuItemButton(
            onPressed: onSelected == null ? null : () => onSelected!(entry.key),
            leadingIcon: Icon(
              entry.key == value ? Icons.check_rounded : null,
              size: 18,
            ),
            child: Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      builder: (context, controller, _) => SizedBox(
        width: width,
        child: Tooltip(
          message: label,
          child: FilledButton.tonal(
            onPressed: onSelected == null
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (width != null)
                  Expanded(
                    child: Text(
                      items[value] ?? label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Text(
                    items[value] ?? label,
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: '最小化',
        icon: const Icon(Icons.remove, size: 18),
        onPressed: () => windowManager.minimize(),
      ),
      IconButton(
        tooltip: '最大化 / 还原',
        icon: const Icon(Icons.crop_square_rounded, size: 16),
        onPressed: () async {
          await windowManager.isMaximized()
              ? await windowManager.unmaximize()
              : await windowManager.maximize();
        },
      ),
      IconButton(
        tooltip: '关闭窗口',
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () => windowManager.close(),
      ),
    ],
  );
}

String formatTime(int seconds) {
  final s = seconds.clamp(0, 999999);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  return '${h > 0 ? '$h:' : ''}${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}
