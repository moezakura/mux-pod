/// マルチプレクサの backend 種別。
enum BackendType {
  /// tmux backend
  tmux,

  /// herdr backend
  herdr;

  /// 文字列表現を返す（JSON 用）。
  String toJson() => name;

  /// JSON 文字列から [BackendType] を復元する。
  ///
  /// 未知の値が与えられた場合は [FormatException] を投げる。
  static BackendType fromJson(String value) => parse(value);

  /// 文字列表現から [BackendType] をパースする。
  ///
  /// 未知の値が与えられた場合は [FormatException] を投げる。
  static BackendType parse(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unknown backend: $value');
  }
}
