import 'package:flutter/material.dart';

import '../../services/version_info.dart';
import '../../l10n/l10n_ext.dart';

/// ライセンス一覧画面
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context),
      child: LicensePage(
        applicationName: 'MuxPod',
        applicationVersion: VersionInfo.version,
        applicationLegalese: l10n.licensesCopyright,
      ),
    );
  }
}
