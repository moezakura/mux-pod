import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../providers/ssh_provider.dart';
import '../../../services/sftp/sftp_browser_service.dart';
import '../../../theme/design_colors.dart';

/// 相対画像の SFTP 解決結果の種別。
enum MarkdownImageResolvedKind {
  /// .md と同じサーバー・同一認証の SFTP で取得（計画 §L2-4・合意#7）。
  sftp,

  /// https/http 絶対 URL（localhost / private IP ブロック通過後のみ）。
  network,

  /// 拒否（placeholder 表示）。data URI・その他スキーム・パストラバーサル等。
  denied,
}

/// 画像リクエストの解決結果（[SftpMarkdownImage.resolveImage] の戻り値）。
class MarkdownImageResolution {
  const MarkdownImageResolution.sftp(String this.sftpPath)
    : kind = MarkdownImageResolvedKind.sftp,
      networkUri = null;

  const MarkdownImageResolution.network(Uri this.networkUri)
    : kind = MarkdownImageResolvedKind.network,
      sftpPath = null;

  const MarkdownImageResolution.denied()
    : kind = MarkdownImageResolvedKind.denied,
      sftpPath = null,
      networkUri = null;

  final MarkdownImageResolvedKind kind;

  /// SFTP で取得する絶対パス（[kind] == sftp のときのみ非 null）。
  final String? sftpPath;

  /// ネットワーク取得する Uri（[kind] == network のときのみ非 null）。
  final Uri? networkUri;
}

/// Markdown のリモート画像を安全に表示するための画像ビルダ部品（#10・#11）。
///
/// [imageBuilder] から呼ばれる [resolveImage] がすべての安全判定（スキーム・
/// IP・パストラバーサル）を行い、判定結果に応じて:
/// - 相対パス → SFTP 解決（[SftpMarkdownImage] で取得・5MB 上限）
/// - https/http（localhost / private IP 以外）→ ネットワーク取得
/// - data URI・その他スキーム・拒否 → placeholder＋alt（合意#7・本フェーズ外）
///
/// ## 相対画像の SFTP 解決（計画 §L3 図 2・合意#7）
/// `.md` のリモートディレクトリ（[MarkdownPreviewScreen] が渡す
/// `entry.fullPath` の親）と結合 → normalize → コンテインメント判定
/// （正規化結果が .md のベースディレクトリ配下でなければ拒否・`../` での
/// 脱出は拒否）→ SftpBrowserService.readFileAsBytes で取得 → Image.memory。
/// 解決は .md と同じサーバー・同一認証の SFTP 経由のため外部 GET なし（SSRF なし）。
///
/// ## セキュリティ（計画 §L2-4・R3/R4/L-2）
/// https/http は任意ホストへの自動 GET（トラッキング・ローカルサービス探索）を
/// 防ぐため localhost / private IP をブロックする。失敗・超過・拒否時は
/// placeholder（アプリは継続）。
class SftpMarkdownImage extends ConsumerStatefulWidget {
  const SftpMarkdownImage({super.key, required this.path, required this.alt});

  /// SFTP で取得する絶対パス（[SftpMarkdownImage.resolveImage] の通過結果）。
  final String path;

  /// 画像の alt テキスト（表示失敗時の placeholder に使う）。
  final String? alt;

  /// 相対画像取得のサイズ上限（5MB・計画 L2-4 の kMaxImageBytes）。
  static const int kMaxImageBytes = 5 * 1024 * 1024;

  /// MarkdownBody の画像リクエスト（Uri）を安全に解決する純関数。
  ///
  /// 判定ロジックを Widget から分離して構造検証（test で Uri を検査）できる
  /// ようにした。副作用なし（sync）。
  ///
  /// - [uri]: MarkdownBody の imageBuilder へ渡される画像 Uri（img の src）
  /// - [mdBaseDirectory]: .md 本体のリモートディレクトリ（`dirname(entry.fullPath)`）
  static MarkdownImageResolution resolveImage({
    required Uri uri,
    required String? mdBaseDirectory,
  }) {
    final scheme = uri.scheme.toLowerCase();

    // スキーム無し = 相対パス（またはルート相対）→ SFTP 解決（合意#7）
    if (scheme.isEmpty) {
      // .md のリモートディレクトリが不明なら解決不能 → 拒否
      final base = mdBaseDirectory;
      if (base == null || base.isEmpty) {
        return const MarkdownImageResolution.denied();
      }
      final String resolved;
      if (uri.path.startsWith('/')) {
        // ルート相対（先頭 /）は .md ディレクトリ配下にならないため
        // コンテインメント判定で拒否される（D-3・ルール明記）。
        resolved = SftpBrowserService.validatePath(uri.path);
      } else {
        // pathSegments は percent-decode 済みで `..` も保持される
        // （dart:core Uri の実装を実測確認）。
        resolved = SftpBrowserService.validatePath(
          p.posix.joinAll([base, ...uri.pathSegments]),
        );
      }
      if (!_isWithinBase(resolved, base)) {
        // パストラバーサル対策: `../` での脱出は拒否（計画 §L3 図 2・LOW-1）
        return const MarkdownImageResolution.denied();
      }
      return MarkdownImageResolution.sftp(resolved);
    }

    // https/http 絶対 URL（scheme ガード・localhost / private IP ブロック）
    if (scheme == 'https' || scheme == 'http') {
      final host = uri.host;
      if (host.isEmpty || isBlockedHost(host)) {
        return const MarkdownImageResolution.denied();
      }
      return MarkdownImageResolution.network(uri);
    }

    // data URI・mailto・ftp・javascript・file 等 → 拒否（placeholder＋alt・
    // 合意#7で data URI デコードは本フェーズ外・Open Questions に明記）
    return const MarkdownImageResolution.denied();
  }

  /// localhost / ループバック / リンクローカル / プライベート IP を検出する。
  ///
  /// ホスト名（パースできない文字列）は許可（DNS リバインディングは対象外）。
  /// 本 SDK の InternetAddress には `isPrivate` / `isAny` が存在しない
  /// （実測確認済み）ため、RFC 1918 を明示判定する。
  static bool isBlockedHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost') return true;

    final addr = InternetAddress.tryParse(lower);
    if (addr == null) return false; // ホスト名 → 許可
    if (addr.isLoopback || addr.isLinkLocal) return true;

    if (addr.type == InternetAddressType.IPv4) {
      return _isBlockedIpv4(addr.rawAddress, 0);
    }

    final raw = addr.rawAddress;
    // IPv4-mapped IPv6（::ffff:0:0/96・例 ::ffff:127.0.0.1）は IPv6 型として
    // パースされ isLoopback/isLinkLocal が false になるため素通りする（実測）。
    // プレフィクス（先頭 10 バイト 0・11-12 バイト目 0xff）を検出し、末尾
    // 4 バイトを IPv4 として再判定してブロックする（R3・MEDIUM-1 対応）。
    final isV4Mapped =
        raw.length == 16 &&
        raw[0] == 0 &&
        raw[1] == 0 &&
        raw[2] == 0 &&
        raw[3] == 0 &&
        raw[4] == 0 &&
        raw[5] == 0 &&
        raw[6] == 0 &&
        raw[7] == 0 &&
        raw[8] == 0 &&
        raw[9] == 0 &&
        raw[10] == 0xFF &&
        raw[11] == 0xFF;
    if (isV4Mapped) {
      return _isBlockedIpv4(raw, 12);
    }
    // ::（unspecified）
    if (raw.every((b) => b == 0)) return true;
    // fc00::/7（unique local）
    if ((raw[0] & 0xFE) == 0xFC) return true;
    return false;
  }

  /// [offset] 以降の 4 バイトを IPv4 として受理可否を判定する。
  ///
  /// プライベート（10./8・172.16/12・192.168/16）・ループバック（127./8）・
  /// リンクローカル（169.254/16）・unspecified（0.0.0.0）をブロックする。
  /// 通常の IPv4 と IPv4-mapped IPv6（::ffff:x.x.x.x）の両方から共用する
  /// （mapped は isLoopback/isLinkLocal が効かないため再判定が必要・MEDIUM-1）。
  static bool _isBlockedIpv4(Uint8List raw, int offset) {
    // 127.0.0.0/8（ループバック）
    if (raw[offset] == 127) return true;
    // 169.254.0.0/16（リンクローカル）
    if (raw[offset] == 169 && raw[offset + 1] == 254) return true;
    // 10.0.0.0/8
    if (raw[offset] == 10) return true;
    // 172.16.0.0/12
    if (raw[offset] == 172 && raw[offset + 1] >= 16 && raw[offset + 1] <= 31) {
      return true;
    }
    // 192.168.0.0/16
    if (raw[offset] == 192 && raw[offset + 1] == 168) return true;
    // 0.0.0.0（unspecified）もブロック（任意アドレス）
    if (raw[offset] == 0 &&
        raw[offset + 1] == 0 &&
        raw[offset + 2] == 0 &&
        raw[offset + 3] == 0) {
      return true;
    }
    return false;
  }

  /// 正規化済みパスがベースディレクトリ配下（同一含む）かを判定する。
  ///
  /// ベースがサーバールート（`/`）のとき（.md がルート直下・例 `/README.md`）
  /// は、ルート配下すべて（先頭 `/` の絶対パス）を許可する。
  /// `p.posix.normalize('/')` は `/` のままで `startsWith('//')` が常に false
  /// になるため全相対画像が誤拒否される（MEDIUM-2・過剰拒否）のを防ぐ。
  static bool _isWithinBase(String path, String baseDirectory) {
    final base = p.posix.normalize(baseDirectory);
    final normalized = p.posix.normalize(path);
    if (base == '/') {
      // validatePath により normalized は常に '/' 始まりの絶対パス
      return normalized.startsWith('/');
    }
    return normalized == base || normalized.startsWith('$base/');
  }

  /// 拒否・失敗時のプレースホルダ（アイコン ＋ alt）。
  ///
  /// alt が空の場合はアイコンのみ表示。[icon] は呼び出し側で種別を
  /// 区別できるように差し替え可能（ブロック時は broken_image・ネットワーク
  /// 取得失敗時は image_not_supported 等）。
  static Widget placeholder({
    required String? alt,
    required String? title,
    required bool isDark,
    double? width,
    double? height,
    IconData icon = Icons.broken_image,
  }) {
    final label = (alt != null && alt.isNotEmpty) ? alt : title;
    final mutedColor = isDark
        ? DesignColors.textMuted
        : DesignColors.textMutedLight;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: DesignColors.textMuted),
            if (label != null && label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: mutedColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  ConsumerState<SftpMarkdownImage> createState() => _SftpMarkdownImageState();
}

class _SftpMarkdownImageState extends ConsumerState<SftpMarkdownImage> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // 非同期完了後の setState を抑止（Widget が破棄済みでも安全に）
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = ref.read(sshProvider.notifier).client;
      if (client == null) {
        throw StateError('SSH client is not available');
      }
      // SftpClient は openSftp() のキャッシュを再利用し close しない
      // （939a298 のチャネル枯渇防止・close 規約 R0）。
      final sftp = await client.openSftp();
      // 上限+1 バイト読み取りの切詰め検知込み（SftpBrowserService 契約）
      final result = await SftpBrowserService.readFileAsBytes(
        sftp,
        widget.path,
        maxBytes: SftpMarkdownImage.kMaxImageBytes,
      );
      if (_disposed) return;
      setState(() => _bytes = result.bytes);
    } catch (_) {
      // 失敗・5MB 超過（PreviewTooLargeException）は placeholder で継続
      if (_disposed) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_failed) {
      return SftpMarkdownImage.placeholder(
        alt: widget.alt,
        title: null,
        isDark: isDark,
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      // 読込中（控えめなインジケータ）
      return const SizedBox(
        width: 120,
        height: 60,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Image.memory(
      bytes,
      errorBuilder: (context, error, stackTrace) =>
          SftpMarkdownImage.placeholder(
            alt: widget.alt,
            title: null,
            isDark: isDark,
          ),
    );
  }
}
