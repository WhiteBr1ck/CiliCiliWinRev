import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_updates.dart';
import '../services/update_download.dart';

Future<void> openUpdateLink(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，请重试')));
  }
}

Future<void> showUpdateDialog(BuildContext context, AppUpdates updates) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updates: updates),
    );

class UpdateDialog extends StatelessWidget {
  final AppUpdates updates;
  const UpdateDialog({super.key, required this.updates});
  String _size(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) {
      final download = updates.download;
      final release = updates.release!;
      final phase = download.phase;
      final downloading = phase == DownloadPhase.downloading;
      final verifying = phase == DownloadPhase.verifying;
      final installing = phase == DownloadPhase.installing;
      final notes = release.notes
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^\s*[#*]+\s*'), '').trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
      return PopScope(
        canPop: !download.busy,
        child: AlertDialog(
          title: Text('新版本 ${release.version}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!download.busy) ...[
                  Text('Windows x64 · ${_size(release.size)}'),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(child: Text(notes)),
                    ),
                  ],
                ],
                if (download.busy) ...[
                  Text(
                    downloading
                        ? '正在下载更新…'
                        : verifying
                        ? '正在校验安装包…'
                        : '正在准备安装…',
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: downloading ? download.progress : null,
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_size(download.received)} / ${_size(download.total)}',
                    ),
                  ],
                ],
                if (phase == DownloadPhase.failed) ...[
                  const SizedBox(height: 16),
                  Text(
                    download.error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!download.busy)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
            if (download.cancellable)
              TextButton(onPressed: download.cancel, child: const Text('取消下载')),
            if (!download.busy)
              FilledButton.icon(
                onPressed: () => unawaited(updates.install()),
                icon: const Icon(Icons.system_update_alt_rounded),
                label: Text(phase == DownloadPhase.failed ? '重试更新' : '立即更新'),
              ),
            if (installing)
              const FilledButton(onPressed: null, child: Text('正在安装…')),
          ],
        ),
      );
    },
  );
}

class UpdateSettings extends StatelessWidget {
  final AppUpdates updates;
  const UpdateSettings({super.key, required this.updates});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) => Column(
      children: [
        SwitchListTile(
          title: const Text('启动时检查更新'),
          value: updates.automatic,
          onChanged: updates.setAutomatic,
        ),
        ListTile(
          title: const Text('软件更新'),
          subtitle: Text(updates.label),
          trailing: OutlinedButton(
            onPressed:
                updates.status == UpdateStatus.checking || updates.download.busy
                ? null
                : () => updates.check(),
            child: const Text('检查更新'),
          ),
        ),
        if (updates.release != null)
          ListTile(
            title: Text('更新至 ${updates.release!.version}'),
            trailing: const Icon(Icons.system_update_alt_rounded),
            onTap: () => showUpdateDialog(context, updates),
          ),
        ListTile(
          title: const Text('GitHub Releases'),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => openUpdateLink(
            context,
            Uri.https('github.com', '/${updates.repository}/releases'),
          ),
        ),
      ],
    ),
  );
}
