import 'package:flutter/material.dart';
import '../app_state.dart';

class DanmakuBar extends StatefulWidget {
  final AppState state;
  final Future<void> Function(String, int, int, String) onSend;
  final ValueChanged<bool> onFocus;
  final ValueChanged<bool> onMenu;
  final bool enabled;
  const DanmakuBar({
    super.key,
    required this.state,
    required this.onSend,
    required this.onFocus,
    required this.onMenu,
    required this.enabled,
  });
  @override
  State<DanmakuBar> createState() => _DanmakuBarState();
}

class _DanmakuBarState extends State<DanmakuBar> {
  final text = TextEditingController();
  int color = 0xFFFFFFFF, type = 0;
  String size = 'M', error = '';
  bool sending = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || !widget.enabled || text.text.trim().isEmpty) return;
    final content = text.text.trim();
    setState(() {
      sending = true;
      error = '';
    });
    try {
      await widget.onSend(content, color, type, size);
      if (mounted) text.clear();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          MenuAnchor(
            onOpen: () => widget.onMenu(true),
            onClose: () => widget.onMenu(false),
            menuChildren: [
              for (final entry in const {
                0xFFFFFFFF: '白色',
                0xFFFFD166: '黄色',
                0xFF80D8FF: '蓝色',
                0xFFFF8FAB: '粉色',
              }.entries)
                MenuItemButton(
                  leadingIcon: Icon(
                    Icons.circle,
                    color: Color(entry.key),
                    size: 18,
                  ),
                  onPressed: () => setState(() => color = entry.key),
                  child: Text(entry.value),
                ),
              const Divider(),
              for (final entry in const {0: '滚动', 1: '顶部', 2: '底部'}.entries)
                MenuItemButton(
                  leadingIcon: Icon(
                    type == entry.key ? Icons.check : null,
                    size: 18,
                  ),
                  onPressed: () => setState(() => type = entry.key),
                  child: Text(entry.value),
                ),
              const Divider(),
              for (final entry in const {'S': '小号', 'M': '标准'}.entries)
                MenuItemButton(
                  leadingIcon: Icon(
                    size == entry.key ? Icons.check : null,
                    size: 18,
                  ),
                  onPressed: () => setState(() => size = entry.key),
                  child: Text(entry.value),
                ),
            ],
            builder: (_, menu, __) => IconButton(
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: const EdgeInsets.all(8),
              tooltip: '弹幕样式',
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              icon: Icon(Icons.palette_outlined, color: Color(color), size: 18),
            ),
          ),
          Expanded(
            child: Focus(
              onFocusChange: widget.onFocus,
              child: TextField(
                key: const Key('danmaku-input'),
                controller: text,
                enabled: widget.enabled && !sending,
                maxLength: 100,
                style: TextStyle(fontSize: 12, color: Color(color)),
                decoration: const InputDecoration(
                  hintText: '发送弹幕',
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                onSubmitted: (_) => send(),
              ),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: const EdgeInsets.all(8),
            key: const Key('danmaku-send'),
            tooltip: '发送弹幕',
            onPressed: widget.enabled && !sending ? send : null,
            icon: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 18),
          ),
          MenuAnchor(
            onOpen: () => widget.onMenu(true),
            onClose: () => widget.onMenu(false),
            menuChildren: [
              SizedBox(
                width: 280,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ListenableBuilder(
                    listenable: widget.state,
                    builder: (_, __) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _slider(
                          '透明度',
                          widget.state.danmakuOpacity,
                          .2,
                          1,
                          (v) => widget.state.setDanmakuStyle(opacity: v),
                          '${(widget.state.danmakuOpacity * 100).round()}%',
                        ),
                        _slider(
                          '字号',
                          widget.state.danmakuFontSize,
                          14,
                          30,
                          (v) => widget.state.setDanmakuStyle(fontSize: v),
                          '${widget.state.danmakuFontSize.round()}',
                        ),
                        _slider(
                          '显示区域',
                          widget.state.danmakuArea,
                          .25,
                          1,
                          (v) => widget.state.setDanmakuStyle(area: v),
                          '${(widget.state.danmakuArea * 100).round()}%',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            builder: (_, menu, __) => IconButton(
              tooltip: '弹幕显示设置',
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: const EdgeInsets.all(8),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              icon: const Icon(Icons.tune_rounded, size: 18),
            ),
          ),
        ],
      ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
    ],
  );
  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
    String label,
  ) => Column(
    children: [
      Row(children: [Text(title), const Spacer(), Text(label)]),
      Slider(value: value, min: min, max: max, onChanged: change),
    ],
  );
}
