import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../services/version_info.dart';
import '../update_controller.dart';
import 'update_messages.dart';

/// Software update page: status, release notes, verification, install.
class UpdateScreen extends ConsumerWidget {
  const UpdateScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const UpdateScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final release = state.release;
    final lastChecked = state.lastChecked;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.updaterTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsVersion),
            subtitle: Text(VersionInfo.version),
          ),
          _StatusCard(state: state),
          SwitchListTile(
            secondary: const Icon(Icons.update),
            title: Text(l10n.updaterAutoCheck),
            subtitle: Text(l10n.updaterAutoCheckDescription),
            value: state.autoCheck,
            onChanged: controller.setAutoCheck,
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(
              lastChecked == null
                  ? l10n.updaterNeverChecked
                  : l10n.updaterLastChecked(
                      DateFormat.yMMMd().add_jm().format(lastChecked),
                    ),
            ),
            subtitle: Text(l10n.updaterSource(controller.source.repo)),
          ),
          if (release != null && release.notes.trim().isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                l10n.updaterReleaseNotes(release.tag),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MarkdownBody(
                data: release.notes,
                onTapLink: (_, href, _) => _open(href),
              ),
            ),
          ],
          if (release != null)
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(l10n.updaterViewOnGitHub),
              onTap: () => _open(release.htmlUrl.toString()),
            ),
        ],
      ),
    );
  }

  static Future<void> _open(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final controller = ref.read(updateControllerProvider.notifier);
    final tag = state.release?.tag ?? '';

    final (IconData icon, String title) = switch (state.phase) {
      UpdatePhase.unsupported || UpdatePhase.idle => (
        Icons.system_update,
        l10n.updaterCheckNow,
      ),
      UpdatePhase.checking => (Icons.sync, l10n.updaterChecking),
      UpdatePhase.upToDate => (Icons.check_circle_outline, l10n.updaterUpToDate),
      UpdatePhase.available => (
        Icons.new_releases_outlined,
        l10n.updaterAvailable(tag),
      ),
      UpdatePhase.downloading => (
        Icons.download,
        l10n.updaterDownloading(((state.progress ?? 0) * 100).round()),
      ),
      UpdatePhase.verifying => (Icons.verified_outlined, l10n.updaterVerifying),
      UpdatePhase.ready => (Icons.verified, l10n.updaterReady(tag)),
      UpdatePhase.installing => (
        Icons.install_mobile,
        l10n.updaterInstalling,
      ),
      UpdatePhase.failed => (Icons.error_outline, l10n.updaterFailed),
    };

    final error = state.error;
    final report = state.report;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: state.phase == UpdatePhase.failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ],
            ),
            if (state.phase == UpdatePhase.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: state.progress),
            ],
            if (state.phase == UpdatePhase.checking ||
                state.phase == UpdatePhase.verifying) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                updateErrorMessage(l10n, error),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (report != null) ...[
              const SizedBox(height: 8),
              _Check(
                ok: true,
                text: report.keyRotated
                    ? l10n.updaterCheckSignatureRotated
                    : l10n.updaterCheckSignature,
              ),
              _Check(ok: true, text: l10n.updaterCheckVersion),
              _Check(
                ok: report.checksumVerified,
                text: report.checksumVerified
                    ? l10n.updaterCheckChecksum
                    : l10n.updaterCheckChecksumMissing,
              ),
            ],
            if (state.needsInstallPermission) ...[
              const SizedBox(height: 8),
              Text(l10n.updaterInstallPermission),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: switch (state.phase) {
                UpdatePhase.unsupported => const [],
                UpdatePhase.idle || UpdatePhase.upToDate => [
                  FilledButton.tonal(
                    onPressed: controller.check,
                    child: Text(l10n.updaterCheckNow),
                  ),
                ],
                UpdatePhase.available => [
                  FilledButton(
                    onPressed: controller.download,
                    child: Text(l10n.updaterDownload),
                  ),
                ],
                UpdatePhase.downloading => [
                  TextButton(
                    onPressed: controller.cancelDownload,
                    child: Text(l10n.updaterCancel),
                  ),
                ],
                UpdatePhase.ready => [
                  FilledButton(
                    onPressed: controller.install,
                    child: Text(l10n.updaterInstall),
                  ),
                ],
                UpdatePhase.failed => [
                  FilledButton.tonal(
                    onPressed: controller.retry,
                    child: Text(l10n.updaterRetry),
                  ),
                ],
                UpdatePhase.checking ||
                UpdatePhase.verifying ||
                UpdatePhase.installing => const [],
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check : Icons.remove,
            size: 18,
            color: ok ? theme.colorScheme.primary : theme.disabledColor,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
