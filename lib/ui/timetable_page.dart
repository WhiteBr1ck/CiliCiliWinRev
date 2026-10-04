import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'components.dart';

class TimetablePage extends StatefulWidget {
  final ClicliApi api;
  final ValueChanged<ScheduleEntry> onOpen;
  const TimetablePage({super.key, required this.api, required this.onOpen});
  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  int year = DateTime.now().year,
      quarter = (DateTime.now().month - 1) ~/ 3 + 1,
      day = 0,
      generation = 0;
  String platform = 'TV/WEB';
  List<ScheduleEntry> items = [];
  bool loading = true;
  String error = '';
  static const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool refresh = false}) async {
    final id = ++generation;
    if (refresh) widget.api.invalidateTimetable(year, quarter);
    setState(() {
      loading = true;
      error = '';
      items = [];
    });
    try {
      final result = await widget.api.timetable(year, quarter: quarter);
      if (mounted && id == generation) {
        setState(() {
          items = result.items;
        });
      }
    } catch (e) {
      if (mounted && id == generation) setState(() => error = '$e');
    } finally {
      if (mounted && id == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = items
        .where(
          (i) =>
              platform == '全部' ||
              (platform == 'TV/WEB'
                  ? ['TV', 'WEB', ''].contains(i.platform)
                  : i.platform == platform),
        )
        .toList();
    final selected = filtered
        .where((i) => day == 0 || (day == 8 ? i.weekday == 0 : i.occursOn(day)))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 12, 30, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppMenu<int>(
                    label: '年份',
                    value: year,
                    items: {
                      for (
                        int y = DateTime.now().year;
                        y >= DateTime.now().year - 3;
                        y--
                      )
                        y: '$y',
                    },
                    onSelected: (y) {
                      setState(() => year = y);
                      load();
                    },
                  ),
                  AppMenu<int>(
                    label: '季度',
                    value: quarter,
                    items: const {
                      1: '1月 · 冬季',
                      2: '4月 · 春季',
                      3: '7月 · 夏季',
                      4: '10月 · 秋季',
                    },
                    onSelected: (q) {
                      setState(() {
                        quarter = q;
                        day = 0;
                      });
                      load();
                    },
                  ),
                  AppMenu<String>(
                    label: '作品类型',
                    value: platform,
                    items: const {
                      'TV/WEB': 'TV / WEB',
                      '全部': '全部类型',
                      'TV': 'TV',
                      'WEB': 'WEB',
                      '剧场版': '剧场版',
                      'OVA': 'OVA',
                    },
                    onSelected: (p) => setState(() => platform = p),
                  ),
                  if (!loading)
                    Tooltip(
                      message: '季度作品',
                      child: Text(
                        '${filtered.length} 部',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  IconButton(
                    tooltip: '刷新时间表',
                    onPressed: loading ? null : () => load(refresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: day == 0,
                    onSelected: (_) => setState(() => day = 0),
                  ),
                  for (int i = 1; i <= 7; i++)
                    ChoiceChip(
                      label: Text(days[i - 1]),
                      selected: day == i,
                      onSelected: (_) => setState(() => day = i),
                    ),
                  ChoiceChip(
                    label: const Text('未定'),
                    selected: day == 8,
                    onSelected: (_) => setState(() => day = 8),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: loading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : error.isNotEmpty
              ? ErrorView(message: error, onRetry: load)
              : selected.isEmpty
              ? const EmptyView(
                  icon: Icons.calendar_month_outlined,
                  title: '暂无排期',
                )
              : LayoutBuilder(
                  builder: (_, box) => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
                    itemCount: selected.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: ((box.maxWidth - 60 + 14) / 324)
                          .floor()
                          .clamp(1, 3),
                      mainAxisExtent: 158,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                    ),
                    itemBuilder: (_, i) {
                      final entry = selected[i],
                          c = Theme.of(context).colorScheme;
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
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 78,
                                    height: 118,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Tooltip(
                                        message: entry.timeSource.isEmpty
                                            ? '暂无可靠播出时间'
                                            : '${entry.timeSource}\n${entry.airingAt?.toIso8601String().split('T').first ?? ''}',
                                        child: Text(
                                          entry.time.isEmpty
                                              ? '--:--'
                                              : entry.time,
                                          style: TextStyle(
                                            color: c.primary,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.anime.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        entry.weekday == 0
                                            ? '排期待定'
                                            : '${(entry.weekdays.isEmpty ? {entry.weekday} : entry.weekdays).map((d) => days[d - 1]).join(' / ')}${entry.timeSource.isEmpty ? '' : ' · ${entry.timeSource.split(' · ').last}'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: c.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.premiere == null
                                            ? entry.anime.status
                                                  .split('·')
                                                  .first
                                                  .trim()
                                            : entry.continuing
                                            ? entry.platform.isEmpty
                                                  ? '续播'
                                                  : '续播 · ${entry.platform}'
                                            : '${entry.platform} · ${entry.premiere!.month.toString().padLeft(2, '0')}-${entry.premiere!.day.toString().padLeft(2, '0')} 首播',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: c.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
