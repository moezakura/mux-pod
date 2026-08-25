import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../theme/design_colors.dart';
import '../../home_screen.dart';
import '../search/settings_search_provider.dart';

/// 設定検索フィールド。
///
/// - autofocus: **無効**（画面表示時にキーボードを自動表示しない）
/// - クエリは [settingsSearchProvider] が正として controller と同期
///   （`ref.listen` で同期 — 検索結果タイルや空状態のクリアなど
///   Provider が更新される経路すべてを controller へ反映する）
/// - タブ離脱（currentTabProvider が Settings=4 以外へ）で unfocus し、
///   キーボードを自動で閉じる（L2-5 イベント表）
class SettingsSearchField extends ConsumerStatefulWidget {
  const SettingsSearchField({super.key});

  @override
  ConsumerState<SettingsSearchField> createState() =>
      _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends ConsumerState<SettingsSearchField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// HomeScreen のタブ順序: 0=Servers, 1=Keys, 2=Dashboard, 3=Notify, 4=Settings。
  /// home_screen.dart は担当外（読み取り専用）のため定数はこちらに持つ。
  static const int _settingsTabIndex = 4;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(settingsSearchProvider));
    // suffix クリアボタン（controller.text 依存）をタイプ入力と同期する。
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    // Provider が正: 外部（検索結果タイル・空状態のクリア等）からの変更を
    // controller へ反映。タイプ入力と同値の更新はスキップされるため、
    // 入力中のカーソル位置は動かない。
    ref.listen(settingsSearchProvider, (prev, query) {
      if (query != _controller.text) {
        _controller.text = query;
      }
    });

    // タブ離脱（Settings タブ以外へ切替）でフォーカスを外す。
    ref.listen(currentTabProvider, (prev, next) {
      if (prev == _settingsTabIndex && next != _settingsTabIndex) {
        _focusNode.unfocus();
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: false,
        onChanged: (value) =>
            ref.read(settingsSearchProvider.notifier).setQuery(value),
        style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: l10n.settingsSearchHint,
          hintStyle: TextStyle(
            fontSize: 14,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: isDark
                ? DesignColors.textMuted
                : DesignColors.textMutedLight,
          ),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: l10n.settingsClearSearch,
                  onPressed: () {
                    _controller.clear();
                    ref.read(settingsSearchProvider.notifier).clear();
                  },
                  color: isDark
                      ? DesignColors.textMuted
                      : DesignColors.textMutedLight,
                )
              : null,
          filled: true,
          fillColor: isDark ? DesignColors.inputDark : DesignColors.inputLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.primary, width: 1),
          ),
        ),
      ),
    );
  }
}
