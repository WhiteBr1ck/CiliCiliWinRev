import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/clicli_api.dart';
import 'account_dialog.dart';
import 'components.dart';

class CommunityPanel extends StatefulWidget {
  final ClicliApi api;
  final AppState state;
  final int videoId;
  const CommunityPanel({
    super.key,
    required this.api,
    required this.state,
    required this.videoId,
  });
  @override
  State<CommunityPanel> createState() => _CommunityPanelState();
}

class _CommunityPanelState extends State<CommunityPanel> {
  List<VodComment> items = [];
  int page = 0, total = 0, generation = 0;
  bool loading = false, posting = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    final id = ++generation, target = more ? page + 1 : 1;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await widget.api.vodComments(widget.videoId, page: target);
      if (!mounted || id != generation) return;
      setState(() {
        items = more ? [...items, ...result.items] : result.items;
        total = result.total;
        page = target;
      });
    } catch (e) {
      if (mounted && id == generation) setState(() => error = '$e');
    } finally {
      if (mounted && id == generation) setState(() => loading = false);
    }
  }

  Future<void> compose({VodComment? reply}) async {
    final account = widget.state.account!;
    if (!account.loggedIn) {
      await showAccountDialog(context, account);
      if (!mounted || !account.loggedIn) return;
    }
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reply == null ? '发表评论' : '回复 ${reply.name}'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 7,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: '评论'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        controller.dispose,
      ),
    );
    if (text == null || !mounted) return;
    setState(() {
      posting = true;
      error = '';
    });
    try {
      try {
        await widget.api.postComment(
          widget.videoId,
          text,
          lastId: reply?.id ?? 0,
        );
      } on ApiException catch (e) {
        if (![429101, 429001].contains(e.code)) rethrow;
        final challenge = e.data?['image_base64'] != null
            ? e.data!
            : await widget.api.commentCaptcha();
        if (!mounted) return;
        final answer = await solveCaptcha(context, challenge);
        if (answer == null) return;
        await widget.api.postComment(
          widget.videoId,
          text,
          lastId: reply?.id ?? 0,
          uuid: answer.uuid,
          dots: answer.dots,
        );
      }
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  Future<void> like(VodComment item) async {
    final account = widget.state.account!;
    if (!account.loggedIn) {
      await showAccountDialog(context, account);
      if (!mounted || !account.loggedIn) return;
    }
    try {
      await widget.api.likeComment(widget.videoId, item);
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> replies(VodComment item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Replies(
        api: widget.api,
        item: item,
        onReply: (i) {
          Navigator.pop(context);
          compose(reply: i);
        },
      ),
    );
  }

  Widget tile(VodComment item) => _CommentTile(
    item: item,
    onReply: () => compose(reply: item),
    onReplies: () => replies(item),
    onLike: () => like(item),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: posting ? null : compose,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('发表评论'),
              ),
            ),
            IconButton(
              tooltip: '刷新评论',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Expanded(
        child: items.isEmpty
            ? loading
                  ? const Center(child: CircularProgressIndicator())
                  : EmptyView(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '暂无评论',
                    )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final item in items) tile(item),
                  if (items.length < total)
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

class _CommentTile extends StatelessWidget {
  final VodComment item;
  final VoidCallback? onReply, onReplies, onLike;
  const _CommentTile({
    required this.item,
    this.onReply,
    this.onReplies,
    this.onLike,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundImage: item.avatar.isEmpty
                  ? null
                  : NetworkImage(item.avatar),
              onBackgroundImageError: item.avatar.isEmpty ? null : (_, __) {},
              child: item.avatar.isEmpty
                  ? const Icon(Icons.person_outline, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (item.replyName.isNotEmpty)
          Text(
            '@${item.replyName}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
            ),
          ),
        SelectableText(
          item.text,
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 4),
        Text(
          item.date.split('T').first,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            if (onLike != null)
              TextButton.icon(
                onPressed: onLike,
                icon: Icon(
                  item.liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  size: 14,
                ),
                label: Text(
                  '${item.likes}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (onReply != null)
              TextButton(
                onPressed: onReply,
                child: const Text('回复', style: TextStyle(fontSize: 11)),
              ),
            if (onReplies != null)
              TextButton(
                onPressed: onReplies,
                child: const Text('查看回复', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const Divider(),
      ],
    ),
  );
}

class _Replies extends StatefulWidget {
  final ClicliApi api;
  final VodComment item;
  final ValueChanged<VodComment> onReply;
  const _Replies({
    required this.api,
    required this.item,
    required this.onReply,
  });
  @override
  State<_Replies> createState() => _RepliesState();
}

class _RepliesState extends State<_Replies> {
  List<VodComment> items = [];
  int total = 0;
  bool loading = false;
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
      final data = await widget.api.replies(
        widget.item.id,
        marker: items.isEmpty ? '' : '${items.last.id}',
      );
      if (mounted) {
        setState(() {
          items.addAll(data.items);
          total = data.total;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .75,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _CommentTile(
          item: widget.item,
          onReply: () => widget.onReply(widget.item),
        ),
        for (final item in items)
          _CommentTile(item: item, onReply: () => widget.onReply(item)),
        if (error.isNotEmpty) ErrorView(message: error, onRetry: load),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (!loading && items.length < total)
          TextButton(onPressed: load, child: const Text('加载更多')),
        if (!loading && items.isEmpty && error.isEmpty)
          const EmptyView(
            icon: Icons.chat_bubble_outline_rounded,
            title: '暂无回复',
          ),
      ],
    ),
  );
}
