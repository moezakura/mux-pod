// inventory: HERDR-PANE-WRITER-000
/// herdr の [PaneWriter] 実装（[HerdrAdapter] mutation ラップ）。
///
/// Phase 2（T13/T14/T15）で capability をフリップし、tmux と同等の操作
/// （send-text / send-keys / focus / split / close / rename / zoom / resize /
/// paste / 画像転送 / workspace・tab CRUD）を解禁した。`copyMode` /
/// `absoluteResize` は設計上 false のまま（herdr に copy-mode は無い・resize は
/// 相対分数のみ Q-04）。画像転送は T15 で解禁した（SFTP アップロードは
/// provider 側・パス注入は `pasteText` = `send-text`）。
///
/// sendKey は [PaneKeyMap] で tmux → herdr 送信経路へ変換し、**全キーで送信
/// 経路が返る**（「送信できないキー」なし・Q-07）:
/// ① 受理キー（F1-F12 / Enter / Tab / Space / Backspace / Escape / 矢印 /
///    C-c）→ `send-keys`
/// ② 拒否キー（Home/End/PgUp/PgDn/Delete/Insert・修飾キー）→ `send-text`
///    でエスケープシーケンスを送信
/// ③ 制御文字（C-d / C-x 等）→ `send-text` で制御文字そのものを送信
library;

import '../../herdr/herdr_adapter.dart';
import '../../herdr/herdr_keymap.dart';
import 'pane_writer.dart';

// inventory: HERDR-PANE-WRITER-001
/// herdr の [PaneWriter] 実装。
class HerdrPaneWriter implements PaneWriter {
  HerdrPaneWriter(this._adapter);

  final HerdrAdapter _adapter;

  /// Phase 2（T13/T14/T15）で解禁した操作能力。
  ///
  /// `copyMode` / `absoluteResize` は設計上 false:
  /// - copyMode: herdr に copy-mode は無い（H7・`pane read` 履歴ベースで
  ///   代替・T15）
  /// - absoluteResize: herdr は相対分数のみ（Q-04）
  ///
  /// `imageTransfer` は T15 で true にフリップした（Q-06）。SFTP アップロード
  /// は `image_transfer_provider.dart` が SSH 直結で行い backend 非依存、
  /// パス注入は `_injectImagePath` → [pasteText]（`send-text`）が担う。
  @override
  PaneCapabilities get capabilities => const PaneCapabilities(
        sendText: true,
        sendKeys: true,
        focus: true,
        split: true,
        close: true,
        rename: true,
        zoom: true,
        resize: true,
        paste: true,
        copyMode: false,
        imageTransfer: true,
        workspaceCrud: true,
        tabCrud: true,
        absoluteResize: false,
      );

  /// tmux キー名を herdr 送信経路へ変換する（Q-07）。
  ///
  /// **全キーで送信経路が返る**（「送信できないキー」なし）。
  @override
  HerdrKeyRoute mapSpecialKey(String tmuxKey) =>
      PaneKeyMap.mapSpecialKey(tmuxKey);

  /// pane へテキストを送信する（`pane send-text`・成功時 stdout 空・R7）。
  @override
  Future<void> sendText(String paneId, String text) async {
    await _adapter.sendText(paneId, text);
  }

  /// pane へ tmux キー名のキーを送信する（Q-07 の 3 経路）。
  ///
  /// 送信経路は [mapSpecialKey] の結果に従う（受理キー = `send-keys`・
  /// 拒否キー = `send-text` + エスケープシーケンス・制御文字 = `send-text` +
  /// 制御文字）。
  @override
  Future<void> sendKey(String paneId, String tmuxKey) async {
    final route = mapSpecialKey(tmuxKey);
    switch (route) {
      case HerdrKeyRouteSendKeys(:final keyName):
        await _adapter.sendKey(paneId, keyName);
      case HerdrKeyRouteSendTextEscape(:final bytes):
        await _adapter.sendText(paneId, bytes);
      case HerdrKeyRouteSendTextControl(:final byte):
        await _adapter.sendText(paneId, String.fromCharCode(byte));
    }
  }

  /// 方向フォーカス（`pane focus --direction`）。
  ///
  /// 隣接 pane なし（`changed:false` + `reason:"no_neighbor"`）は soft 失敗として
  /// [PaneOperationNoopException] を投げる（UI は情報通知「その方向に pane は
  /// ありません」・S4/T19/T20）。[resizePane] と同じ no-op パターン。
  @override
  Future<void> focusPaneDirection(String paneId, String direction) async {
    final result = await _adapter.focusDirection(paneId, direction);
    if (!result.changed) {
      throw PaneOperationNoopException(
        operation: 'focusPaneDirection',
        reason: result.reason ?? 'no_neighbor',
      );
    }
  }

  /// 分割（`pane split`・応答は layout を含まないため反映は snapshot 同期）。
  @override
  Future<void> splitPane(
    String paneId,
    String direction, {
    double? ratio,
    String? cwd,
  }) async {
    await _adapter.splitPane(paneId, direction, ratio: ratio, cwd: cwd);
  }

  /// pane を閉じる（**破壊的 close の唯一経路**・Q-03。対象不在は
  /// [HerdrTargetNotFoundException]）。
  @override
  Future<void> closePane(String paneId) async {
    await _adapter.closePane(paneId);
  }

  /// ラベル変更（`pane rename`）。
  @override
  Future<void> renamePane(String paneId, String label) async {
    await _adapter.renamePane(paneId, label);
  }

  /// zoom（`pane zoom`・[mode]: `'toggle'` / `'on'` / `'off'`）。
  @override
  Future<void> zoomPane(String paneId, {String mode = 'toggle'}) async {
    await _adapter.zoomPane(paneId, mode: mode);
  }

  /// 相対分数 resize（Q-04・`pane resize --direction --amount`）。
  ///
  /// 分割境界外（`changed:false` + `reason:"unchanged"`）は soft 失敗として
  /// [PaneOperationNoopException] を投げる（UI は情報通知・S4）。
  @override
  Future<void> resizePane(String paneId, String direction, double amount) async {
    final result = await _adapter.resizePane(paneId, direction, amount);
    if (!result.changed) {
      throw PaneOperationNoopException(
        operation: 'resizePane',
        reason: result.reason ?? 'unchanged',
      );
    }
  }

  /// 複数行貼り付け（Q-06: `send-text` で代替。`send-text` はバイナリ素通し・
  /// G4 実測）。
  @override
  Future<void> pasteText(String paneId, String text) async {
    await _adapter.sendText(paneId, text);
  }

  // ===== 未対応 or 未配線（設計判断）=====

  /// 直接 pane 選択（`pane focus --pane <target>` 単体コマンドが存在しない・
  /// OQ1）。
  ///
  /// herdr では方向 focus + edges 反復（[focusPaneDirection]）で代替する。
  /// UI の herdr セレクタは表示切替コミット（`_switchHerdrTarget`）を経由し
  /// このメソッドを呼ばないため、型付き例外で明示する（R4/R9）。
  @override
  Future<void> selectPane(String paneId) => _unsupported('selectPane');

  /// tab を作成する（`herdr tab create`・Q-05）。
  ///
  /// [label] と [focus] は [HerdrAdapter.tabCreate] へそのまま透過する
  /// （label は snapshot の `tabs[].label` に反映される表示名・focus は作成後の
  /// フォーカス移動を制御）。
  @override
  Future<void> createTab(
    String workspaceId, {
    String? label,
    bool? focus,
  }) async {
    await _adapter.tabCreate(workspaceId, label: label, focus: focus);
  }

  /// tab を閉じる（`herdr tab close`・Q-05。対象不在は
  /// [HerdrTargetNotFoundException]）。
  @override
  Future<void> closeTab(String tabId) async {
    await _adapter.tabClose(tabId);
  }

  /// tab のラベルを変更する（`herdr tab rename`・Q-05）。
  @override
  Future<void> renameTab(String tabId, String label) async {
    await _adapter.tabRename(tabId, label);
  }

  /// tab へフォーカスする（`herdr tab focus`・Q-05）。
  @override
  Future<void> focusTab(String tabId) async {
    await _adapter.tabFocus(tabId);
  }

  /// workspace を作成する（`herdr workspace create`・Q-05）。
  @override
  Future<void> createWorkspace(String label) async {
    await _adapter.workspaceCreate(label: label);
  }

  /// workspace を閉じる（`herdr workspace close`・Q-05。対象不在は
  /// [HerdrTargetNotFoundException]）。
  @override
  Future<void> closeWorkspace(String workspaceId) async {
    await _adapter.workspaceClose(workspaceId);
  }

  /// workspace のラベルを変更する（`herdr workspace rename`・Q-05）。
  @override
  Future<void> renameWorkspace(String workspaceId, String label) async {
    await _adapter.workspaceRename(workspaceId, label);
  }

  /// workspace へフォーカスする（`herdr workspace focus`・Q-05）。
  @override
  Future<void> focusWorkspace(String workspaceId) async {
    await _adapter.workspaceFocus(workspaceId);
  }

  /// 画像転送（T15: 解禁済み）。
  ///
  /// 実際の画像転送フローは「SFTP アップロード（`image_transfer_provider.dart`
  /// が SSH 直結で実行・backend 非依存）→ `_injectImagePath` が [pasteText]
  /// （`send-text`）でパス送信」の 2 段構成で、paneId を必要とする。interface の
  /// [PaneWriter.imageTransfer] は paneId を持たないため直接は呼ばれず、型付き
  /// 例外で明示する（`_injectImagePath` 経路が正・R4/R9）。
  @override
  Future<void> imageTransfer(String path) => throw UnsupportedPaneOperationException(
        operation: 'imageTransfer',
        backend: 'herdr',
        message: '画像転送は _injectImagePath（SFTP アップロード + send-text）経路で行います',
      );

  Never _unsupported(String operation) => throw UnsupportedPaneOperationException(
        operation: operation,
        backend: 'herdr',
        message: 'この操作は herdr で未対応です',
      );
}
