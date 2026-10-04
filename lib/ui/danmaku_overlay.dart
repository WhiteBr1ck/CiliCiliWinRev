import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models.dart';

/// Server timestamps remain authoritative. Overloaded lanes are dropped.
class DanmakuOverlay extends StatefulWidget {
  final List<DanmakuEntry> items;
  final double position, rate;
  final bool playing;
  final double opacity, fontSize, area;
  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.position,
    required this.playing,
    required this.rate,
    this.opacity = .8,
    this.fontSize = 18,
    this.area = .5,
  });
  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  final clock = Stopwatch();
  double position = 0;
  @override
  void initState() {
    super.initState();
    ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    sync();
  }

  @override
  void didUpdateWidget(DanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position ||
        old.playing != widget.playing ||
        old.rate != widget.rate) {
      sync();
    }
  }

  void sync() {
    position = widget.position;
    clock
      ..reset()
      ..stop();
    if (widget.playing) {
      clock.start();
      if (!ticker.isActive) ticker.start();
    } else {
      if (ticker.isActive) ticker.stop();
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, box) {
        final now =
            position +
            (clock.elapsedMicroseconds / 1000000).clamp(0, .75) * widget.rate;
        final lineHeight = widget.fontSize + 12;
        final lanes = ((box.maxHeight - 160) * widget.area / lineHeight)
            .floor()
            .clamp(1, 12);
        final until = [
          for (int i = 0; i < 3; i++) List<double>.filled(lanes, -100),
        ];
        final placements = <({DanmakuEntry item, int lane, double width})>[];
        final sorted = widget.items.toList()
          ..sort((a, b) {
            final order = a.time.compareTo(b.time);
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
        for (final item in sorted) {
          if (item.time > now) break;
          final age = now - item.time;
          if (age > 60 || item.type != 0 && age > 5) continue;
          final fontSize = widget.fontSize * (item.size == 'S' ? .82 : 1);
          final painter = TextPainter(
            text: TextSpan(
              text: item.text,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          final lane = until[item.type].indexWhere((t) => t <= item.time);
          if (lane < 0) continue;
          // Equal speed prevents shorter following comments from catching up.
          until[item.type][lane] =
              item.time + (item.type == 0 ? (width + 48) / 140 : 5);
          final lifetime = item.type == 0 ? (box.maxWidth + width) / 140 : 5;
          if (age < lifetime) {
            placements.add((item: item, lane: lane, width: width));
          }
        }
        return ClipRect(
          child: Stack(
            children: [
              for (final p in placements)
                Positioned(
                  top: p.item.type == 2
                      ? (box.maxHeight - 160 - (p.lane + 1) * lineHeight).clamp(
                          0,
                          box.maxHeight,
                        )
                      : 24 + p.lane * lineHeight,
                  left: p.item.type == 0
                      ? box.maxWidth - (now - p.item.time) * 140
                      : (box.maxWidth - p.width) / 2,
                  child: Text(
                    p.item.text,
                    maxLines: 1,
                    style: TextStyle(
                      color: Color(
                        p.item.color,
                      ).withValues(alpha: widget.opacity),
                      fontSize:
                          widget.fontSize * (p.item.size == 'S' ? .82 : 1),
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 4,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
