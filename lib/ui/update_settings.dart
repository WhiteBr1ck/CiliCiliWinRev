import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_updates.dart';

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

Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release,
) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text('新版本 ${release.version}'),
    content: release.size > 0
        ? Text(
            'Windows x64 · ${(release.size / 1048576).toStringAsFixed(1)} MB',
          )
        : const Text('Windows x64'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
      TextButton(
        onPressed: () => openUpdateLink(ctx, release.page),
        child: const Text('发行说明'),
      ),
      FilledButton.icon(
        onPressed: () => openUpdateLink(ctx, release.installer),
        icon: const Icon(Icons.download_rounded),
        label: const Text('下载安装包'),
      ),
    ],
  ),
);

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
            onPressed: updates.status == UpdateStatus.checking
                ? null
                : () => updates.check(),
            child: const Text('检查更新'),
          ),
        ),
        if (updates.release != null)
          ListTile(
            title: Text('安装 ${updates.release!.version}'),
            trailing: const Icon(Icons.download_rounded),
            onTap: () => showUpdateDialog(context, updates.release!),
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
