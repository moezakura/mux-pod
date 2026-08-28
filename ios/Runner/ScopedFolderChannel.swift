import Flutter
import UIKit

/// `mux.pod/scoped_folder` MethodChannel の実装。
///
/// iOS の「セキュリティスコープ付きフォルダ」操作を Flutter 側へ提供する。
/// Flutter 標準には「フォルダ選択 + スコープアクセス開始/終了」をまとめて行う API が
/// 無いため、ネイティブで `UIDocumentPickerViewController` によるフォルダ選択と、
/// 選択フォルダへのセキュリティスコープ付きアクセスの開始/終了を実装する。
///
/// 提供メソッド:
/// - `pickFolder`: フォルダ選択ダイアログを表示。選択時は
///   `URL.bookmarkData(options: .withSecurityScope)` を base64 エンコードして返す。
///   キャンセル時は nil、ブックマーク生成失敗時は FlutterError。
/// - `startScope`(bookmark): base64 ブックマークを復号→ `URL(resolvingBookmarkData:)`
///   で URL 化→ `startAccessingSecurityScopedResource()` でアクセス開始→フォルダの
///   ファイルパスを返す。ブックマーク不正・stale・アクセス開始失敗は FlutterError。
/// - `stopScope`: `startScope` で開始したアクセスを
///   `stopAccessingSecurityScopedResource()` で終了する。
///
/// - Note: このファイルは Linux 環境のためコンパイル検証ができない。API は iOS 15 向け
///   （deployment target 15.0）に書いてあるが、実機/Xcode ビルドでの確認を推奨する。
///   （セルフレビュー）
final class ScopedFolderChannel: NSObject, UIDocumentPickerDelegate {
  private let viewController: UIViewController
  private var pickResult: FlutterResult?
  private var activeScopeURL: URL?

  /// チャンネルを生成し、メソッドハンドラを登録する。
  init(channel: FlutterMethodChannel, viewController: UIViewController) {
    self.viewController = viewController
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  // MARK: - Method handling

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickFolder":
      pickFolder(result: result)
    case "startScope":
      guard let bookmark = call.arguments as? String, !bookmark.isEmpty else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "bookmark (base64) is required",
          details: nil
        ))
        return
      }
      startScope(bookmark: bookmark, result: result)
    case "stopScope":
      stopScope()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - pickFolder

  private func pickFolder(result: @escaping FlutterResult) {
    guard pickResult == nil else {
      result(FlutterError(
        code: "busy",
        message: "folder picker is already active",
        details: nil
      ))
      return
    }
    pickResult = result

    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    viewController.present(picker, animated: true)
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    let result = pickResult
    pickResult = nil
    guard let url = urls.first else {
      result?(nil)
      return
    }

    // ブックマーク生成のために一時的にスコープアクセスを開始する。
    let didStart = url.startAccessingSecurityScopedResource()
    var bookmark: Data?
    if didStart {
      bookmark = try? url.bookmarkData(options: .withSecurityScope)
      url.stopAccessingSecurityScopedResource()
    }

    if let data = bookmark {
      result?(data.base64EncodedString())
    } else {
      result?(FlutterError(
        code: "bookmark_failed",
        message: "could not create security-scoped bookmark",
        details: nil
      ))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pickResult
    pickResult = nil
    result?(nil)
  }

  // MARK: - startScope / stopScope

  private func startScope(bookmark: String, result: @escaping FlutterResult) {
    // 既にアクティブなスコープを閉じてから開始する（多重開始を防ぐ）。
    stopScope()

    guard let data = Data(base64Encoded: bookmark) else {
      result(FlutterError(
        code: "invalid_bookmark",
        message: "base64 decode failed",
        details: nil
      ))
      return
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      result(FlutterError(
        code: "resolve_failed",
        message: "could not resolve bookmark",
        details: nil
      ))
      return
    }

    guard url.startAccessingSecurityScopedResource() else {
      result(FlutterError(
        code: "scope_failed",
        message: "could not start security-scoped access",
        details: nil
      ))
      return
    }

    if isStale {
      // stale ブックマークは再選択が必要（エラーで返す）。開始したアクセスは閉じる。
      url.stopAccessingSecurityScopedResource()
      result(FlutterError(
        code: "stale_bookmark",
        message: "bookmark is stale; please pick the folder again",
        details: nil
      ))
      return
    }

    activeScopeURL = url
    result(url.path)
  }

  private func stopScope() {
    if let url = activeScopeURL {
      url.stopAccessingSecurityScopedResource()
      activeScopeURL = nil
    }
  }
}
