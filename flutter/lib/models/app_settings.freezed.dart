// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) {
  return _AppSettings.fromJson(json);
}

/// @nodoc
mixin _$AppSettings {
  /// 表示設定
  DisplaySettings get display => throw _privateConstructorUsedError;

  /// ターミナル設定
  TerminalSettings get terminal => throw _privateConstructorUsedError;

  /// SSH設定
  SshSettings get ssh => throw _privateConstructorUsedError;

  /// セキュリティ設定
  SecuritySettings get security => throw _privateConstructorUsedError;

  /// Serializes this AppSettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AppSettingsCopyWith<AppSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppSettingsCopyWith<$Res> {
  factory $AppSettingsCopyWith(
          AppSettings value, $Res Function(AppSettings) then) =
      _$AppSettingsCopyWithImpl<$Res, AppSettings>;
  @useResult
  $Res call(
      {DisplaySettings display,
      TerminalSettings terminal,
      SshSettings ssh,
      SecuritySettings security});

  $DisplaySettingsCopyWith<$Res> get display;
  $TerminalSettingsCopyWith<$Res> get terminal;
  $SshSettingsCopyWith<$Res> get ssh;
  $SecuritySettingsCopyWith<$Res> get security;
}

/// @nodoc
class _$AppSettingsCopyWithImpl<$Res, $Val extends AppSettings>
    implements $AppSettingsCopyWith<$Res> {
  _$AppSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? display = null,
    Object? terminal = null,
    Object? ssh = null,
    Object? security = null,
  }) {
    return _then(_value.copyWith(
      display: null == display
          ? _value.display
          : display // ignore: cast_nullable_to_non_nullable
              as DisplaySettings,
      terminal: null == terminal
          ? _value.terminal
          : terminal // ignore: cast_nullable_to_non_nullable
              as TerminalSettings,
      ssh: null == ssh
          ? _value.ssh
          : ssh // ignore: cast_nullable_to_non_nullable
              as SshSettings,
      security: null == security
          ? _value.security
          : security // ignore: cast_nullable_to_non_nullable
              as SecuritySettings,
    ) as $Val);
  }

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $DisplaySettingsCopyWith<$Res> get display {
    return $DisplaySettingsCopyWith<$Res>(_value.display, (value) {
      return _then(_value.copyWith(display: value) as $Val);
    });
  }

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TerminalSettingsCopyWith<$Res> get terminal {
    return $TerminalSettingsCopyWith<$Res>(_value.terminal, (value) {
      return _then(_value.copyWith(terminal: value) as $Val);
    });
  }

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SshSettingsCopyWith<$Res> get ssh {
    return $SshSettingsCopyWith<$Res>(_value.ssh, (value) {
      return _then(_value.copyWith(ssh: value) as $Val);
    });
  }

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SecuritySettingsCopyWith<$Res> get security {
    return $SecuritySettingsCopyWith<$Res>(_value.security, (value) {
      return _then(_value.copyWith(security: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$AppSettingsImplCopyWith<$Res>
    implements $AppSettingsCopyWith<$Res> {
  factory _$$AppSettingsImplCopyWith(
          _$AppSettingsImpl value, $Res Function(_$AppSettingsImpl) then) =
      __$$AppSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {DisplaySettings display,
      TerminalSettings terminal,
      SshSettings ssh,
      SecuritySettings security});

  @override
  $DisplaySettingsCopyWith<$Res> get display;
  @override
  $TerminalSettingsCopyWith<$Res> get terminal;
  @override
  $SshSettingsCopyWith<$Res> get ssh;
  @override
  $SecuritySettingsCopyWith<$Res> get security;
}

/// @nodoc
class __$$AppSettingsImplCopyWithImpl<$Res>
    extends _$AppSettingsCopyWithImpl<$Res, _$AppSettingsImpl>
    implements _$$AppSettingsImplCopyWith<$Res> {
  __$$AppSettingsImplCopyWithImpl(
      _$AppSettingsImpl _value, $Res Function(_$AppSettingsImpl) _then)
      : super(_value, _then);

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? display = null,
    Object? terminal = null,
    Object? ssh = null,
    Object? security = null,
  }) {
    return _then(_$AppSettingsImpl(
      display: null == display
          ? _value.display
          : display // ignore: cast_nullable_to_non_nullable
              as DisplaySettings,
      terminal: null == terminal
          ? _value.terminal
          : terminal // ignore: cast_nullable_to_non_nullable
              as TerminalSettings,
      ssh: null == ssh
          ? _value.ssh
          : ssh // ignore: cast_nullable_to_non_nullable
              as SshSettings,
      security: null == security
          ? _value.security
          : security // ignore: cast_nullable_to_non_nullable
              as SecuritySettings,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AppSettingsImpl extends _AppSettings {
  const _$AppSettingsImpl(
      {this.display = const DisplaySettings(),
      this.terminal = const TerminalSettings(),
      this.ssh = const SshSettings(),
      this.security = const SecuritySettings()})
      : super._();

  factory _$AppSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppSettingsImplFromJson(json);

  /// 表示設定
  @override
  @JsonKey()
  final DisplaySettings display;

  /// ターミナル設定
  @override
  @JsonKey()
  final TerminalSettings terminal;

  /// SSH設定
  @override
  @JsonKey()
  final SshSettings ssh;

  /// セキュリティ設定
  @override
  @JsonKey()
  final SecuritySettings security;

  @override
  String toString() {
    return 'AppSettings(display: $display, terminal: $terminal, ssh: $ssh, security: $security)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppSettingsImpl &&
            (identical(other.display, display) || other.display == display) &&
            (identical(other.terminal, terminal) ||
                other.terminal == terminal) &&
            (identical(other.ssh, ssh) || other.ssh == ssh) &&
            (identical(other.security, security) ||
                other.security == security));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, display, terminal, ssh, security);

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AppSettingsImplCopyWith<_$AppSettingsImpl> get copyWith =>
      __$$AppSettingsImplCopyWithImpl<_$AppSettingsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AppSettingsImplToJson(
      this,
    );
  }
}

abstract class _AppSettings extends AppSettings {
  const factory _AppSettings(
      {final DisplaySettings display,
      final TerminalSettings terminal,
      final SshSettings ssh,
      final SecuritySettings security}) = _$AppSettingsImpl;
  const _AppSettings._() : super._();

  factory _AppSettings.fromJson(Map<String, dynamic> json) =
      _$AppSettingsImpl.fromJson;

  /// 表示設定
  @override
  DisplaySettings get display;

  /// ターミナル設定
  @override
  TerminalSettings get terminal;

  /// SSH設定
  @override
  SshSettings get ssh;

  /// セキュリティ設定
  @override
  SecuritySettings get security;

  /// Create a copy of AppSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AppSettingsImplCopyWith<_$AppSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DisplaySettings _$DisplaySettingsFromJson(Map<String, dynamic> json) {
  return _DisplaySettings.fromJson(json);
}

/// @nodoc
mixin _$DisplaySettings {
  /// ダークモード
  bool get darkMode => throw _privateConstructorUsedError;

  /// システムテーマに従う
  bool get useSystemTheme => throw _privateConstructorUsedError;

  /// 画面の向き固定
  bool get lockOrientation => throw _privateConstructorUsedError;

  /// 画面常時点灯
  bool get keepScreenOn => throw _privateConstructorUsedError;

  /// フルスクリーンモード
  bool get fullScreen => throw _privateConstructorUsedError;

  /// ステータスバー表示
  bool get showStatusBar => throw _privateConstructorUsedError;

  /// Serializes this DisplaySettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DisplaySettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DisplaySettingsCopyWith<DisplaySettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DisplaySettingsCopyWith<$Res> {
  factory $DisplaySettingsCopyWith(
          DisplaySettings value, $Res Function(DisplaySettings) then) =
      _$DisplaySettingsCopyWithImpl<$Res, DisplaySettings>;
  @useResult
  $Res call(
      {bool darkMode,
      bool useSystemTheme,
      bool lockOrientation,
      bool keepScreenOn,
      bool fullScreen,
      bool showStatusBar});
}

/// @nodoc
class _$DisplaySettingsCopyWithImpl<$Res, $Val extends DisplaySettings>
    implements $DisplaySettingsCopyWith<$Res> {
  _$DisplaySettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DisplaySettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? darkMode = null,
    Object? useSystemTheme = null,
    Object? lockOrientation = null,
    Object? keepScreenOn = null,
    Object? fullScreen = null,
    Object? showStatusBar = null,
  }) {
    return _then(_value.copyWith(
      darkMode: null == darkMode
          ? _value.darkMode
          : darkMode // ignore: cast_nullable_to_non_nullable
              as bool,
      useSystemTheme: null == useSystemTheme
          ? _value.useSystemTheme
          : useSystemTheme // ignore: cast_nullable_to_non_nullable
              as bool,
      lockOrientation: null == lockOrientation
          ? _value.lockOrientation
          : lockOrientation // ignore: cast_nullable_to_non_nullable
              as bool,
      keepScreenOn: null == keepScreenOn
          ? _value.keepScreenOn
          : keepScreenOn // ignore: cast_nullable_to_non_nullable
              as bool,
      fullScreen: null == fullScreen
          ? _value.fullScreen
          : fullScreen // ignore: cast_nullable_to_non_nullable
              as bool,
      showStatusBar: null == showStatusBar
          ? _value.showStatusBar
          : showStatusBar // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DisplaySettingsImplCopyWith<$Res>
    implements $DisplaySettingsCopyWith<$Res> {
  factory _$$DisplaySettingsImplCopyWith(_$DisplaySettingsImpl value,
          $Res Function(_$DisplaySettingsImpl) then) =
      __$$DisplaySettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool darkMode,
      bool useSystemTheme,
      bool lockOrientation,
      bool keepScreenOn,
      bool fullScreen,
      bool showStatusBar});
}

/// @nodoc
class __$$DisplaySettingsImplCopyWithImpl<$Res>
    extends _$DisplaySettingsCopyWithImpl<$Res, _$DisplaySettingsImpl>
    implements _$$DisplaySettingsImplCopyWith<$Res> {
  __$$DisplaySettingsImplCopyWithImpl(
      _$DisplaySettingsImpl _value, $Res Function(_$DisplaySettingsImpl) _then)
      : super(_value, _then);

  /// Create a copy of DisplaySettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? darkMode = null,
    Object? useSystemTheme = null,
    Object? lockOrientation = null,
    Object? keepScreenOn = null,
    Object? fullScreen = null,
    Object? showStatusBar = null,
  }) {
    return _then(_$DisplaySettingsImpl(
      darkMode: null == darkMode
          ? _value.darkMode
          : darkMode // ignore: cast_nullable_to_non_nullable
              as bool,
      useSystemTheme: null == useSystemTheme
          ? _value.useSystemTheme
          : useSystemTheme // ignore: cast_nullable_to_non_nullable
              as bool,
      lockOrientation: null == lockOrientation
          ? _value.lockOrientation
          : lockOrientation // ignore: cast_nullable_to_non_nullable
              as bool,
      keepScreenOn: null == keepScreenOn
          ? _value.keepScreenOn
          : keepScreenOn // ignore: cast_nullable_to_non_nullable
              as bool,
      fullScreen: null == fullScreen
          ? _value.fullScreen
          : fullScreen // ignore: cast_nullable_to_non_nullable
              as bool,
      showStatusBar: null == showStatusBar
          ? _value.showStatusBar
          : showStatusBar // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DisplaySettingsImpl extends _DisplaySettings {
  const _$DisplaySettingsImpl(
      {this.darkMode = true,
      this.useSystemTheme = true,
      this.lockOrientation = false,
      this.keepScreenOn = true,
      this.fullScreen = false,
      this.showStatusBar = true})
      : super._();

  factory _$DisplaySettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$DisplaySettingsImplFromJson(json);

  /// ダークモード
  @override
  @JsonKey()
  final bool darkMode;

  /// システムテーマに従う
  @override
  @JsonKey()
  final bool useSystemTheme;

  /// 画面の向き固定
  @override
  @JsonKey()
  final bool lockOrientation;

  /// 画面常時点灯
  @override
  @JsonKey()
  final bool keepScreenOn;

  /// フルスクリーンモード
  @override
  @JsonKey()
  final bool fullScreen;

  /// ステータスバー表示
  @override
  @JsonKey()
  final bool showStatusBar;

  @override
  String toString() {
    return 'DisplaySettings(darkMode: $darkMode, useSystemTheme: $useSystemTheme, lockOrientation: $lockOrientation, keepScreenOn: $keepScreenOn, fullScreen: $fullScreen, showStatusBar: $showStatusBar)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DisplaySettingsImpl &&
            (identical(other.darkMode, darkMode) ||
                other.darkMode == darkMode) &&
            (identical(other.useSystemTheme, useSystemTheme) ||
                other.useSystemTheme == useSystemTheme) &&
            (identical(other.lockOrientation, lockOrientation) ||
                other.lockOrientation == lockOrientation) &&
            (identical(other.keepScreenOn, keepScreenOn) ||
                other.keepScreenOn == keepScreenOn) &&
            (identical(other.fullScreen, fullScreen) ||
                other.fullScreen == fullScreen) &&
            (identical(other.showStatusBar, showStatusBar) ||
                other.showStatusBar == showStatusBar));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, darkMode, useSystemTheme,
      lockOrientation, keepScreenOn, fullScreen, showStatusBar);

  /// Create a copy of DisplaySettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DisplaySettingsImplCopyWith<_$DisplaySettingsImpl> get copyWith =>
      __$$DisplaySettingsImplCopyWithImpl<_$DisplaySettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DisplaySettingsImplToJson(
      this,
    );
  }
}

abstract class _DisplaySettings extends DisplaySettings {
  const factory _DisplaySettings(
      {final bool darkMode,
      final bool useSystemTheme,
      final bool lockOrientation,
      final bool keepScreenOn,
      final bool fullScreen,
      final bool showStatusBar}) = _$DisplaySettingsImpl;
  const _DisplaySettings._() : super._();

  factory _DisplaySettings.fromJson(Map<String, dynamic> json) =
      _$DisplaySettingsImpl.fromJson;

  /// ダークモード
  @override
  bool get darkMode;

  /// システムテーマに従う
  @override
  bool get useSystemTheme;

  /// 画面の向き固定
  @override
  bool get lockOrientation;

  /// 画面常時点灯
  @override
  bool get keepScreenOn;

  /// フルスクリーンモード
  @override
  bool get fullScreen;

  /// ステータスバー表示
  @override
  bool get showStatusBar;

  /// Create a copy of DisplaySettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DisplaySettingsImplCopyWith<_$DisplaySettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TerminalSettings _$TerminalSettingsFromJson(Map<String, dynamic> json) {
  return _TerminalSettings.fromJson(json);
}

/// @nodoc
mixin _$TerminalSettings {
  /// フォントファミリー
  FontFamily get fontFamily => throw _privateConstructorUsedError;

  /// フォントサイズ
  double get fontSize => throw _privateConstructorUsedError;

  /// 行間
  double get lineHeight => throw _privateConstructorUsedError;

  /// カラーテーマ
  ColorTheme get colorTheme => throw _privateConstructorUsedError;

  /// カーソルブリンク
  bool get cursorBlink => throw _privateConstructorUsedError;

  /// カーソルスタイル（block, underline, bar）
  String get cursorStyle => throw _privateConstructorUsedError;

  /// スクロールバック行数
  int get scrollbackLines => throw _privateConstructorUsedError;

  /// ベル音
  bool get bellSound => throw _privateConstructorUsedError;

  /// ベル振動
  bool get bellVibrate => throw _privateConstructorUsedError;

  /// 特殊キーバー表示
  bool get showSpecialKeysBar => throw _privateConstructorUsedError;

  /// コピー時に自動選択解除
  bool get autoClearSelection => throw _privateConstructorUsedError;

  /// ダブルタップで単語選択
  bool get doubleTapSelectWord => throw _privateConstructorUsedError;

  /// トリプルタップで行選択
  bool get tripleTapSelectLine => throw _privateConstructorUsedError;

  /// 長押しでコンテキストメニュー
  bool get longPressContextMenu => throw _privateConstructorUsedError;

  /// ピンチでズーム
  bool get pinchToZoom => throw _privateConstructorUsedError;

  /// 最小フォントサイズ
  double get minFontSize => throw _privateConstructorUsedError;

  /// 最大フォントサイズ
  double get maxFontSize => throw _privateConstructorUsedError;

  /// Serializes this TerminalSettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TerminalSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TerminalSettingsCopyWith<TerminalSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TerminalSettingsCopyWith<$Res> {
  factory $TerminalSettingsCopyWith(
          TerminalSettings value, $Res Function(TerminalSettings) then) =
      _$TerminalSettingsCopyWithImpl<$Res, TerminalSettings>;
  @useResult
  $Res call(
      {FontFamily fontFamily,
      double fontSize,
      double lineHeight,
      ColorTheme colorTheme,
      bool cursorBlink,
      String cursorStyle,
      int scrollbackLines,
      bool bellSound,
      bool bellVibrate,
      bool showSpecialKeysBar,
      bool autoClearSelection,
      bool doubleTapSelectWord,
      bool tripleTapSelectLine,
      bool longPressContextMenu,
      bool pinchToZoom,
      double minFontSize,
      double maxFontSize});
}

/// @nodoc
class _$TerminalSettingsCopyWithImpl<$Res, $Val extends TerminalSettings>
    implements $TerminalSettingsCopyWith<$Res> {
  _$TerminalSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TerminalSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fontFamily = null,
    Object? fontSize = null,
    Object? lineHeight = null,
    Object? colorTheme = null,
    Object? cursorBlink = null,
    Object? cursorStyle = null,
    Object? scrollbackLines = null,
    Object? bellSound = null,
    Object? bellVibrate = null,
    Object? showSpecialKeysBar = null,
    Object? autoClearSelection = null,
    Object? doubleTapSelectWord = null,
    Object? tripleTapSelectLine = null,
    Object? longPressContextMenu = null,
    Object? pinchToZoom = null,
    Object? minFontSize = null,
    Object? maxFontSize = null,
  }) {
    return _then(_value.copyWith(
      fontFamily: null == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as FontFamily,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double,
      lineHeight: null == lineHeight
          ? _value.lineHeight
          : lineHeight // ignore: cast_nullable_to_non_nullable
              as double,
      colorTheme: null == colorTheme
          ? _value.colorTheme
          : colorTheme // ignore: cast_nullable_to_non_nullable
              as ColorTheme,
      cursorBlink: null == cursorBlink
          ? _value.cursorBlink
          : cursorBlink // ignore: cast_nullable_to_non_nullable
              as bool,
      cursorStyle: null == cursorStyle
          ? _value.cursorStyle
          : cursorStyle // ignore: cast_nullable_to_non_nullable
              as String,
      scrollbackLines: null == scrollbackLines
          ? _value.scrollbackLines
          : scrollbackLines // ignore: cast_nullable_to_non_nullable
              as int,
      bellSound: null == bellSound
          ? _value.bellSound
          : bellSound // ignore: cast_nullable_to_non_nullable
              as bool,
      bellVibrate: null == bellVibrate
          ? _value.bellVibrate
          : bellVibrate // ignore: cast_nullable_to_non_nullable
              as bool,
      showSpecialKeysBar: null == showSpecialKeysBar
          ? _value.showSpecialKeysBar
          : showSpecialKeysBar // ignore: cast_nullable_to_non_nullable
              as bool,
      autoClearSelection: null == autoClearSelection
          ? _value.autoClearSelection
          : autoClearSelection // ignore: cast_nullable_to_non_nullable
              as bool,
      doubleTapSelectWord: null == doubleTapSelectWord
          ? _value.doubleTapSelectWord
          : doubleTapSelectWord // ignore: cast_nullable_to_non_nullable
              as bool,
      tripleTapSelectLine: null == tripleTapSelectLine
          ? _value.tripleTapSelectLine
          : tripleTapSelectLine // ignore: cast_nullable_to_non_nullable
              as bool,
      longPressContextMenu: null == longPressContextMenu
          ? _value.longPressContextMenu
          : longPressContextMenu // ignore: cast_nullable_to_non_nullable
              as bool,
      pinchToZoom: null == pinchToZoom
          ? _value.pinchToZoom
          : pinchToZoom // ignore: cast_nullable_to_non_nullable
              as bool,
      minFontSize: null == minFontSize
          ? _value.minFontSize
          : minFontSize // ignore: cast_nullable_to_non_nullable
              as double,
      maxFontSize: null == maxFontSize
          ? _value.maxFontSize
          : maxFontSize // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TerminalSettingsImplCopyWith<$Res>
    implements $TerminalSettingsCopyWith<$Res> {
  factory _$$TerminalSettingsImplCopyWith(_$TerminalSettingsImpl value,
          $Res Function(_$TerminalSettingsImpl) then) =
      __$$TerminalSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {FontFamily fontFamily,
      double fontSize,
      double lineHeight,
      ColorTheme colorTheme,
      bool cursorBlink,
      String cursorStyle,
      int scrollbackLines,
      bool bellSound,
      bool bellVibrate,
      bool showSpecialKeysBar,
      bool autoClearSelection,
      bool doubleTapSelectWord,
      bool tripleTapSelectLine,
      bool longPressContextMenu,
      bool pinchToZoom,
      double minFontSize,
      double maxFontSize});
}

/// @nodoc
class __$$TerminalSettingsImplCopyWithImpl<$Res>
    extends _$TerminalSettingsCopyWithImpl<$Res, _$TerminalSettingsImpl>
    implements _$$TerminalSettingsImplCopyWith<$Res> {
  __$$TerminalSettingsImplCopyWithImpl(_$TerminalSettingsImpl _value,
      $Res Function(_$TerminalSettingsImpl) _then)
      : super(_value, _then);

  /// Create a copy of TerminalSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fontFamily = null,
    Object? fontSize = null,
    Object? lineHeight = null,
    Object? colorTheme = null,
    Object? cursorBlink = null,
    Object? cursorStyle = null,
    Object? scrollbackLines = null,
    Object? bellSound = null,
    Object? bellVibrate = null,
    Object? showSpecialKeysBar = null,
    Object? autoClearSelection = null,
    Object? doubleTapSelectWord = null,
    Object? tripleTapSelectLine = null,
    Object? longPressContextMenu = null,
    Object? pinchToZoom = null,
    Object? minFontSize = null,
    Object? maxFontSize = null,
  }) {
    return _then(_$TerminalSettingsImpl(
      fontFamily: null == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as FontFamily,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double,
      lineHeight: null == lineHeight
          ? _value.lineHeight
          : lineHeight // ignore: cast_nullable_to_non_nullable
              as double,
      colorTheme: null == colorTheme
          ? _value.colorTheme
          : colorTheme // ignore: cast_nullable_to_non_nullable
              as ColorTheme,
      cursorBlink: null == cursorBlink
          ? _value.cursorBlink
          : cursorBlink // ignore: cast_nullable_to_non_nullable
              as bool,
      cursorStyle: null == cursorStyle
          ? _value.cursorStyle
          : cursorStyle // ignore: cast_nullable_to_non_nullable
              as String,
      scrollbackLines: null == scrollbackLines
          ? _value.scrollbackLines
          : scrollbackLines // ignore: cast_nullable_to_non_nullable
              as int,
      bellSound: null == bellSound
          ? _value.bellSound
          : bellSound // ignore: cast_nullable_to_non_nullable
              as bool,
      bellVibrate: null == bellVibrate
          ? _value.bellVibrate
          : bellVibrate // ignore: cast_nullable_to_non_nullable
              as bool,
      showSpecialKeysBar: null == showSpecialKeysBar
          ? _value.showSpecialKeysBar
          : showSpecialKeysBar // ignore: cast_nullable_to_non_nullable
              as bool,
      autoClearSelection: null == autoClearSelection
          ? _value.autoClearSelection
          : autoClearSelection // ignore: cast_nullable_to_non_nullable
              as bool,
      doubleTapSelectWord: null == doubleTapSelectWord
          ? _value.doubleTapSelectWord
          : doubleTapSelectWord // ignore: cast_nullable_to_non_nullable
              as bool,
      tripleTapSelectLine: null == tripleTapSelectLine
          ? _value.tripleTapSelectLine
          : tripleTapSelectLine // ignore: cast_nullable_to_non_nullable
              as bool,
      longPressContextMenu: null == longPressContextMenu
          ? _value.longPressContextMenu
          : longPressContextMenu // ignore: cast_nullable_to_non_nullable
              as bool,
      pinchToZoom: null == pinchToZoom
          ? _value.pinchToZoom
          : pinchToZoom // ignore: cast_nullable_to_non_nullable
              as bool,
      minFontSize: null == minFontSize
          ? _value.minFontSize
          : minFontSize // ignore: cast_nullable_to_non_nullable
              as double,
      maxFontSize: null == maxFontSize
          ? _value.maxFontSize
          : maxFontSize // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TerminalSettingsImpl extends _TerminalSettings {
  const _$TerminalSettingsImpl(
      {this.fontFamily = FontFamily.jetBrainsMono,
      this.fontSize = 14.0,
      this.lineHeight = 1.2,
      this.colorTheme = ColorTheme.dracula,
      this.cursorBlink = true,
      this.cursorStyle = 'block',
      this.scrollbackLines = 10000,
      this.bellSound = true,
      this.bellVibrate = true,
      this.showSpecialKeysBar = true,
      this.autoClearSelection = true,
      this.doubleTapSelectWord = true,
      this.tripleTapSelectLine = true,
      this.longPressContextMenu = true,
      this.pinchToZoom = true,
      this.minFontSize = 8.0,
      this.maxFontSize = 32.0})
      : super._();

  factory _$TerminalSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$TerminalSettingsImplFromJson(json);

  /// フォントファミリー
  @override
  @JsonKey()
  final FontFamily fontFamily;

  /// フォントサイズ
  @override
  @JsonKey()
  final double fontSize;

  /// 行間
  @override
  @JsonKey()
  final double lineHeight;

  /// カラーテーマ
  @override
  @JsonKey()
  final ColorTheme colorTheme;

  /// カーソルブリンク
  @override
  @JsonKey()
  final bool cursorBlink;

  /// カーソルスタイル（block, underline, bar）
  @override
  @JsonKey()
  final String cursorStyle;

  /// スクロールバック行数
  @override
  @JsonKey()
  final int scrollbackLines;

  /// ベル音
  @override
  @JsonKey()
  final bool bellSound;

  /// ベル振動
  @override
  @JsonKey()
  final bool bellVibrate;

  /// 特殊キーバー表示
  @override
  @JsonKey()
  final bool showSpecialKeysBar;

  /// コピー時に自動選択解除
  @override
  @JsonKey()
  final bool autoClearSelection;

  /// ダブルタップで単語選択
  @override
  @JsonKey()
  final bool doubleTapSelectWord;

  /// トリプルタップで行選択
  @override
  @JsonKey()
  final bool tripleTapSelectLine;

  /// 長押しでコンテキストメニュー
  @override
  @JsonKey()
  final bool longPressContextMenu;

  /// ピンチでズーム
  @override
  @JsonKey()
  final bool pinchToZoom;

  /// 最小フォントサイズ
  @override
  @JsonKey()
  final double minFontSize;

  /// 最大フォントサイズ
  @override
  @JsonKey()
  final double maxFontSize;

  @override
  String toString() {
    return 'TerminalSettings(fontFamily: $fontFamily, fontSize: $fontSize, lineHeight: $lineHeight, colorTheme: $colorTheme, cursorBlink: $cursorBlink, cursorStyle: $cursorStyle, scrollbackLines: $scrollbackLines, bellSound: $bellSound, bellVibrate: $bellVibrate, showSpecialKeysBar: $showSpecialKeysBar, autoClearSelection: $autoClearSelection, doubleTapSelectWord: $doubleTapSelectWord, tripleTapSelectLine: $tripleTapSelectLine, longPressContextMenu: $longPressContextMenu, pinchToZoom: $pinchToZoom, minFontSize: $minFontSize, maxFontSize: $maxFontSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TerminalSettingsImpl &&
            (identical(other.fontFamily, fontFamily) ||
                other.fontFamily == fontFamily) &&
            (identical(other.fontSize, fontSize) ||
                other.fontSize == fontSize) &&
            (identical(other.lineHeight, lineHeight) ||
                other.lineHeight == lineHeight) &&
            (identical(other.colorTheme, colorTheme) ||
                other.colorTheme == colorTheme) &&
            (identical(other.cursorBlink, cursorBlink) ||
                other.cursorBlink == cursorBlink) &&
            (identical(other.cursorStyle, cursorStyle) ||
                other.cursorStyle == cursorStyle) &&
            (identical(other.scrollbackLines, scrollbackLines) ||
                other.scrollbackLines == scrollbackLines) &&
            (identical(other.bellSound, bellSound) ||
                other.bellSound == bellSound) &&
            (identical(other.bellVibrate, bellVibrate) ||
                other.bellVibrate == bellVibrate) &&
            (identical(other.showSpecialKeysBar, showSpecialKeysBar) ||
                other.showSpecialKeysBar == showSpecialKeysBar) &&
            (identical(other.autoClearSelection, autoClearSelection) ||
                other.autoClearSelection == autoClearSelection) &&
            (identical(other.doubleTapSelectWord, doubleTapSelectWord) ||
                other.doubleTapSelectWord == doubleTapSelectWord) &&
            (identical(other.tripleTapSelectLine, tripleTapSelectLine) ||
                other.tripleTapSelectLine == tripleTapSelectLine) &&
            (identical(other.longPressContextMenu, longPressContextMenu) ||
                other.longPressContextMenu == longPressContextMenu) &&
            (identical(other.pinchToZoom, pinchToZoom) ||
                other.pinchToZoom == pinchToZoom) &&
            (identical(other.minFontSize, minFontSize) ||
                other.minFontSize == minFontSize) &&
            (identical(other.maxFontSize, maxFontSize) ||
                other.maxFontSize == maxFontSize));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      fontFamily,
      fontSize,
      lineHeight,
      colorTheme,
      cursorBlink,
      cursorStyle,
      scrollbackLines,
      bellSound,
      bellVibrate,
      showSpecialKeysBar,
      autoClearSelection,
      doubleTapSelectWord,
      tripleTapSelectLine,
      longPressContextMenu,
      pinchToZoom,
      minFontSize,
      maxFontSize);

  /// Create a copy of TerminalSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TerminalSettingsImplCopyWith<_$TerminalSettingsImpl> get copyWith =>
      __$$TerminalSettingsImplCopyWithImpl<_$TerminalSettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TerminalSettingsImplToJson(
      this,
    );
  }
}

abstract class _TerminalSettings extends TerminalSettings {
  const factory _TerminalSettings(
      {final FontFamily fontFamily,
      final double fontSize,
      final double lineHeight,
      final ColorTheme colorTheme,
      final bool cursorBlink,
      final String cursorStyle,
      final int scrollbackLines,
      final bool bellSound,
      final bool bellVibrate,
      final bool showSpecialKeysBar,
      final bool autoClearSelection,
      final bool doubleTapSelectWord,
      final bool tripleTapSelectLine,
      final bool longPressContextMenu,
      final bool pinchToZoom,
      final double minFontSize,
      final double maxFontSize}) = _$TerminalSettingsImpl;
  const _TerminalSettings._() : super._();

  factory _TerminalSettings.fromJson(Map<String, dynamic> json) =
      _$TerminalSettingsImpl.fromJson;

  /// フォントファミリー
  @override
  FontFamily get fontFamily;

  /// フォントサイズ
  @override
  double get fontSize;

  /// 行間
  @override
  double get lineHeight;

  /// カラーテーマ
  @override
  ColorTheme get colorTheme;

  /// カーソルブリンク
  @override
  bool get cursorBlink;

  /// カーソルスタイル（block, underline, bar）
  @override
  String get cursorStyle;

  /// スクロールバック行数
  @override
  int get scrollbackLines;

  /// ベル音
  @override
  bool get bellSound;

  /// ベル振動
  @override
  bool get bellVibrate;

  /// 特殊キーバー表示
  @override
  bool get showSpecialKeysBar;

  /// コピー時に自動選択解除
  @override
  bool get autoClearSelection;

  /// ダブルタップで単語選択
  @override
  bool get doubleTapSelectWord;

  /// トリプルタップで行選択
  @override
  bool get tripleTapSelectLine;

  /// 長押しでコンテキストメニュー
  @override
  bool get longPressContextMenu;

  /// ピンチでズーム
  @override
  bool get pinchToZoom;

  /// 最小フォントサイズ
  @override
  double get minFontSize;

  /// 最大フォントサイズ
  @override
  double get maxFontSize;

  /// Create a copy of TerminalSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TerminalSettingsImplCopyWith<_$TerminalSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SshSettings _$SshSettingsFromJson(Map<String, dynamic> json) {
  return _SshSettings.fromJson(json);
}

/// @nodoc
mixin _$SshSettings {
  /// 接続タイムアウト（秒）
  int get connectionTimeout => throw _privateConstructorUsedError;

  /// キープアライブ間隔（秒）
  int get keepAliveInterval => throw _privateConstructorUsedError;

  /// 再接続試行回数
  int get reconnectAttempts => throw _privateConstructorUsedError;

  /// 再接続待機時間（秒）
  int get reconnectDelay => throw _privateConstructorUsedError;

  /// 圧縮有効
  bool get compression => throw _privateConstructorUsedError;

  /// デフォルトのPTY幅
  int get defaultPtyWidth => throw _privateConstructorUsedError;

  /// デフォルトのPTY高さ
  int get defaultPtyHeight => throw _privateConstructorUsedError;

  /// デフォルトのTERM
  String get defaultTerm => throw _privateConstructorUsedError;

  /// Serializes this SshSettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SshSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SshSettingsCopyWith<SshSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SshSettingsCopyWith<$Res> {
  factory $SshSettingsCopyWith(
          SshSettings value, $Res Function(SshSettings) then) =
      _$SshSettingsCopyWithImpl<$Res, SshSettings>;
  @useResult
  $Res call(
      {int connectionTimeout,
      int keepAliveInterval,
      int reconnectAttempts,
      int reconnectDelay,
      bool compression,
      int defaultPtyWidth,
      int defaultPtyHeight,
      String defaultTerm});
}

/// @nodoc
class _$SshSettingsCopyWithImpl<$Res, $Val extends SshSettings>
    implements $SshSettingsCopyWith<$Res> {
  _$SshSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SshSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connectionTimeout = null,
    Object? keepAliveInterval = null,
    Object? reconnectAttempts = null,
    Object? reconnectDelay = null,
    Object? compression = null,
    Object? defaultPtyWidth = null,
    Object? defaultPtyHeight = null,
    Object? defaultTerm = null,
  }) {
    return _then(_value.copyWith(
      connectionTimeout: null == connectionTimeout
          ? _value.connectionTimeout
          : connectionTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      keepAliveInterval: null == keepAliveInterval
          ? _value.keepAliveInterval
          : keepAliveInterval // ignore: cast_nullable_to_non_nullable
              as int,
      reconnectAttempts: null == reconnectAttempts
          ? _value.reconnectAttempts
          : reconnectAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      reconnectDelay: null == reconnectDelay
          ? _value.reconnectDelay
          : reconnectDelay // ignore: cast_nullable_to_non_nullable
              as int,
      compression: null == compression
          ? _value.compression
          : compression // ignore: cast_nullable_to_non_nullable
              as bool,
      defaultPtyWidth: null == defaultPtyWidth
          ? _value.defaultPtyWidth
          : defaultPtyWidth // ignore: cast_nullable_to_non_nullable
              as int,
      defaultPtyHeight: null == defaultPtyHeight
          ? _value.defaultPtyHeight
          : defaultPtyHeight // ignore: cast_nullable_to_non_nullable
              as int,
      defaultTerm: null == defaultTerm
          ? _value.defaultTerm
          : defaultTerm // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SshSettingsImplCopyWith<$Res>
    implements $SshSettingsCopyWith<$Res> {
  factory _$$SshSettingsImplCopyWith(
          _$SshSettingsImpl value, $Res Function(_$SshSettingsImpl) then) =
      __$$SshSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int connectionTimeout,
      int keepAliveInterval,
      int reconnectAttempts,
      int reconnectDelay,
      bool compression,
      int defaultPtyWidth,
      int defaultPtyHeight,
      String defaultTerm});
}

/// @nodoc
class __$$SshSettingsImplCopyWithImpl<$Res>
    extends _$SshSettingsCopyWithImpl<$Res, _$SshSettingsImpl>
    implements _$$SshSettingsImplCopyWith<$Res> {
  __$$SshSettingsImplCopyWithImpl(
      _$SshSettingsImpl _value, $Res Function(_$SshSettingsImpl) _then)
      : super(_value, _then);

  /// Create a copy of SshSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connectionTimeout = null,
    Object? keepAliveInterval = null,
    Object? reconnectAttempts = null,
    Object? reconnectDelay = null,
    Object? compression = null,
    Object? defaultPtyWidth = null,
    Object? defaultPtyHeight = null,
    Object? defaultTerm = null,
  }) {
    return _then(_$SshSettingsImpl(
      connectionTimeout: null == connectionTimeout
          ? _value.connectionTimeout
          : connectionTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      keepAliveInterval: null == keepAliveInterval
          ? _value.keepAliveInterval
          : keepAliveInterval // ignore: cast_nullable_to_non_nullable
              as int,
      reconnectAttempts: null == reconnectAttempts
          ? _value.reconnectAttempts
          : reconnectAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      reconnectDelay: null == reconnectDelay
          ? _value.reconnectDelay
          : reconnectDelay // ignore: cast_nullable_to_non_nullable
              as int,
      compression: null == compression
          ? _value.compression
          : compression // ignore: cast_nullable_to_non_nullable
              as bool,
      defaultPtyWidth: null == defaultPtyWidth
          ? _value.defaultPtyWidth
          : defaultPtyWidth // ignore: cast_nullable_to_non_nullable
              as int,
      defaultPtyHeight: null == defaultPtyHeight
          ? _value.defaultPtyHeight
          : defaultPtyHeight // ignore: cast_nullable_to_non_nullable
              as int,
      defaultTerm: null == defaultTerm
          ? _value.defaultTerm
          : defaultTerm // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SshSettingsImpl extends _SshSettings {
  const _$SshSettingsImpl(
      {this.connectionTimeout = 30,
      this.keepAliveInterval = 60,
      this.reconnectAttempts = 3,
      this.reconnectDelay = 5,
      this.compression = false,
      this.defaultPtyWidth = 80,
      this.defaultPtyHeight = 24,
      this.defaultTerm = 'xterm-256color'})
      : super._();

  factory _$SshSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$SshSettingsImplFromJson(json);

  /// 接続タイムアウト（秒）
  @override
  @JsonKey()
  final int connectionTimeout;

  /// キープアライブ間隔（秒）
  @override
  @JsonKey()
  final int keepAliveInterval;

  /// 再接続試行回数
  @override
  @JsonKey()
  final int reconnectAttempts;

  /// 再接続待機時間（秒）
  @override
  @JsonKey()
  final int reconnectDelay;

  /// 圧縮有効
  @override
  @JsonKey()
  final bool compression;

  /// デフォルトのPTY幅
  @override
  @JsonKey()
  final int defaultPtyWidth;

  /// デフォルトのPTY高さ
  @override
  @JsonKey()
  final int defaultPtyHeight;

  /// デフォルトのTERM
  @override
  @JsonKey()
  final String defaultTerm;

  @override
  String toString() {
    return 'SshSettings(connectionTimeout: $connectionTimeout, keepAliveInterval: $keepAliveInterval, reconnectAttempts: $reconnectAttempts, reconnectDelay: $reconnectDelay, compression: $compression, defaultPtyWidth: $defaultPtyWidth, defaultPtyHeight: $defaultPtyHeight, defaultTerm: $defaultTerm)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SshSettingsImpl &&
            (identical(other.connectionTimeout, connectionTimeout) ||
                other.connectionTimeout == connectionTimeout) &&
            (identical(other.keepAliveInterval, keepAliveInterval) ||
                other.keepAliveInterval == keepAliveInterval) &&
            (identical(other.reconnectAttempts, reconnectAttempts) ||
                other.reconnectAttempts == reconnectAttempts) &&
            (identical(other.reconnectDelay, reconnectDelay) ||
                other.reconnectDelay == reconnectDelay) &&
            (identical(other.compression, compression) ||
                other.compression == compression) &&
            (identical(other.defaultPtyWidth, defaultPtyWidth) ||
                other.defaultPtyWidth == defaultPtyWidth) &&
            (identical(other.defaultPtyHeight, defaultPtyHeight) ||
                other.defaultPtyHeight == defaultPtyHeight) &&
            (identical(other.defaultTerm, defaultTerm) ||
                other.defaultTerm == defaultTerm));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      connectionTimeout,
      keepAliveInterval,
      reconnectAttempts,
      reconnectDelay,
      compression,
      defaultPtyWidth,
      defaultPtyHeight,
      defaultTerm);

  /// Create a copy of SshSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SshSettingsImplCopyWith<_$SshSettingsImpl> get copyWith =>
      __$$SshSettingsImplCopyWithImpl<_$SshSettingsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SshSettingsImplToJson(
      this,
    );
  }
}

abstract class _SshSettings extends SshSettings {
  const factory _SshSettings(
      {final int connectionTimeout,
      final int keepAliveInterval,
      final int reconnectAttempts,
      final int reconnectDelay,
      final bool compression,
      final int defaultPtyWidth,
      final int defaultPtyHeight,
      final String defaultTerm}) = _$SshSettingsImpl;
  const _SshSettings._() : super._();

  factory _SshSettings.fromJson(Map<String, dynamic> json) =
      _$SshSettingsImpl.fromJson;

  /// 接続タイムアウト（秒）
  @override
  int get connectionTimeout;

  /// キープアライブ間隔（秒）
  @override
  int get keepAliveInterval;

  /// 再接続試行回数
  @override
  int get reconnectAttempts;

  /// 再接続待機時間（秒）
  @override
  int get reconnectDelay;

  /// 圧縮有効
  @override
  bool get compression;

  /// デフォルトのPTY幅
  @override
  int get defaultPtyWidth;

  /// デフォルトのPTY高さ
  @override
  int get defaultPtyHeight;

  /// デフォルトのTERM
  @override
  String get defaultTerm;

  /// Create a copy of SshSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SshSettingsImplCopyWith<_$SshSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SecuritySettings _$SecuritySettingsFromJson(Map<String, dynamic> json) {
  return _SecuritySettings.fromJson(json);
}

/// @nodoc
mixin _$SecuritySettings {
  /// 生体認証でロック解除
  bool get biometricUnlock => throw _privateConstructorUsedError;

  /// アプリ起動時に認証を要求
  bool get requireAuthOnLaunch => throw _privateConstructorUsedError;

  /// バックグラウンド時に認証を要求
  bool get requireAuthOnResume => throw _privateConstructorUsedError;

  /// 認証タイムアウト（秒）
  int get authTimeout => throw _privateConstructorUsedError;

  /// クリップボード自動クリア（秒、0で無効）
  int get clipboardClearTimeout => throw _privateConstructorUsedError;

  /// 画面キャプチャを許可
  bool get allowScreenCapture => throw _privateConstructorUsedError;

  /// パスワード表示を許可
  bool get allowShowPassword => throw _privateConstructorUsedError;

  /// 秘密鍵表示を許可
  bool get allowShowPrivateKey => throw _privateConstructorUsedError;

  /// Serializes this SecuritySettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SecuritySettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SecuritySettingsCopyWith<SecuritySettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SecuritySettingsCopyWith<$Res> {
  factory $SecuritySettingsCopyWith(
          SecuritySettings value, $Res Function(SecuritySettings) then) =
      _$SecuritySettingsCopyWithImpl<$Res, SecuritySettings>;
  @useResult
  $Res call(
      {bool biometricUnlock,
      bool requireAuthOnLaunch,
      bool requireAuthOnResume,
      int authTimeout,
      int clipboardClearTimeout,
      bool allowScreenCapture,
      bool allowShowPassword,
      bool allowShowPrivateKey});
}

/// @nodoc
class _$SecuritySettingsCopyWithImpl<$Res, $Val extends SecuritySettings>
    implements $SecuritySettingsCopyWith<$Res> {
  _$SecuritySettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SecuritySettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? biometricUnlock = null,
    Object? requireAuthOnLaunch = null,
    Object? requireAuthOnResume = null,
    Object? authTimeout = null,
    Object? clipboardClearTimeout = null,
    Object? allowScreenCapture = null,
    Object? allowShowPassword = null,
    Object? allowShowPrivateKey = null,
  }) {
    return _then(_value.copyWith(
      biometricUnlock: null == biometricUnlock
          ? _value.biometricUnlock
          : biometricUnlock // ignore: cast_nullable_to_non_nullable
              as bool,
      requireAuthOnLaunch: null == requireAuthOnLaunch
          ? _value.requireAuthOnLaunch
          : requireAuthOnLaunch // ignore: cast_nullable_to_non_nullable
              as bool,
      requireAuthOnResume: null == requireAuthOnResume
          ? _value.requireAuthOnResume
          : requireAuthOnResume // ignore: cast_nullable_to_non_nullable
              as bool,
      authTimeout: null == authTimeout
          ? _value.authTimeout
          : authTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      clipboardClearTimeout: null == clipboardClearTimeout
          ? _value.clipboardClearTimeout
          : clipboardClearTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      allowScreenCapture: null == allowScreenCapture
          ? _value.allowScreenCapture
          : allowScreenCapture // ignore: cast_nullable_to_non_nullable
              as bool,
      allowShowPassword: null == allowShowPassword
          ? _value.allowShowPassword
          : allowShowPassword // ignore: cast_nullable_to_non_nullable
              as bool,
      allowShowPrivateKey: null == allowShowPrivateKey
          ? _value.allowShowPrivateKey
          : allowShowPrivateKey // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SecuritySettingsImplCopyWith<$Res>
    implements $SecuritySettingsCopyWith<$Res> {
  factory _$$SecuritySettingsImplCopyWith(_$SecuritySettingsImpl value,
          $Res Function(_$SecuritySettingsImpl) then) =
      __$$SecuritySettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool biometricUnlock,
      bool requireAuthOnLaunch,
      bool requireAuthOnResume,
      int authTimeout,
      int clipboardClearTimeout,
      bool allowScreenCapture,
      bool allowShowPassword,
      bool allowShowPrivateKey});
}

/// @nodoc
class __$$SecuritySettingsImplCopyWithImpl<$Res>
    extends _$SecuritySettingsCopyWithImpl<$Res, _$SecuritySettingsImpl>
    implements _$$SecuritySettingsImplCopyWith<$Res> {
  __$$SecuritySettingsImplCopyWithImpl(_$SecuritySettingsImpl _value,
      $Res Function(_$SecuritySettingsImpl) _then)
      : super(_value, _then);

  /// Create a copy of SecuritySettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? biometricUnlock = null,
    Object? requireAuthOnLaunch = null,
    Object? requireAuthOnResume = null,
    Object? authTimeout = null,
    Object? clipboardClearTimeout = null,
    Object? allowScreenCapture = null,
    Object? allowShowPassword = null,
    Object? allowShowPrivateKey = null,
  }) {
    return _then(_$SecuritySettingsImpl(
      biometricUnlock: null == biometricUnlock
          ? _value.biometricUnlock
          : biometricUnlock // ignore: cast_nullable_to_non_nullable
              as bool,
      requireAuthOnLaunch: null == requireAuthOnLaunch
          ? _value.requireAuthOnLaunch
          : requireAuthOnLaunch // ignore: cast_nullable_to_non_nullable
              as bool,
      requireAuthOnResume: null == requireAuthOnResume
          ? _value.requireAuthOnResume
          : requireAuthOnResume // ignore: cast_nullable_to_non_nullable
              as bool,
      authTimeout: null == authTimeout
          ? _value.authTimeout
          : authTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      clipboardClearTimeout: null == clipboardClearTimeout
          ? _value.clipboardClearTimeout
          : clipboardClearTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      allowScreenCapture: null == allowScreenCapture
          ? _value.allowScreenCapture
          : allowScreenCapture // ignore: cast_nullable_to_non_nullable
              as bool,
      allowShowPassword: null == allowShowPassword
          ? _value.allowShowPassword
          : allowShowPassword // ignore: cast_nullable_to_non_nullable
              as bool,
      allowShowPrivateKey: null == allowShowPrivateKey
          ? _value.allowShowPrivateKey
          : allowShowPrivateKey // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SecuritySettingsImpl extends _SecuritySettings {
  const _$SecuritySettingsImpl(
      {this.biometricUnlock = false,
      this.requireAuthOnLaunch = false,
      this.requireAuthOnResume = false,
      this.authTimeout = 300,
      this.clipboardClearTimeout = 60,
      this.allowScreenCapture = true,
      this.allowShowPassword = false,
      this.allowShowPrivateKey = false})
      : super._();

  factory _$SecuritySettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$SecuritySettingsImplFromJson(json);

  /// 生体認証でロック解除
  @override
  @JsonKey()
  final bool biometricUnlock;

  /// アプリ起動時に認証を要求
  @override
  @JsonKey()
  final bool requireAuthOnLaunch;

  /// バックグラウンド時に認証を要求
  @override
  @JsonKey()
  final bool requireAuthOnResume;

  /// 認証タイムアウト（秒）
  @override
  @JsonKey()
  final int authTimeout;

  /// クリップボード自動クリア（秒、0で無効）
  @override
  @JsonKey()
  final int clipboardClearTimeout;

  /// 画面キャプチャを許可
  @override
  @JsonKey()
  final bool allowScreenCapture;

  /// パスワード表示を許可
  @override
  @JsonKey()
  final bool allowShowPassword;

  /// 秘密鍵表示を許可
  @override
  @JsonKey()
  final bool allowShowPrivateKey;

  @override
  String toString() {
    return 'SecuritySettings(biometricUnlock: $biometricUnlock, requireAuthOnLaunch: $requireAuthOnLaunch, requireAuthOnResume: $requireAuthOnResume, authTimeout: $authTimeout, clipboardClearTimeout: $clipboardClearTimeout, allowScreenCapture: $allowScreenCapture, allowShowPassword: $allowShowPassword, allowShowPrivateKey: $allowShowPrivateKey)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SecuritySettingsImpl &&
            (identical(other.biometricUnlock, biometricUnlock) ||
                other.biometricUnlock == biometricUnlock) &&
            (identical(other.requireAuthOnLaunch, requireAuthOnLaunch) ||
                other.requireAuthOnLaunch == requireAuthOnLaunch) &&
            (identical(other.requireAuthOnResume, requireAuthOnResume) ||
                other.requireAuthOnResume == requireAuthOnResume) &&
            (identical(other.authTimeout, authTimeout) ||
                other.authTimeout == authTimeout) &&
            (identical(other.clipboardClearTimeout, clipboardClearTimeout) ||
                other.clipboardClearTimeout == clipboardClearTimeout) &&
            (identical(other.allowScreenCapture, allowScreenCapture) ||
                other.allowScreenCapture == allowScreenCapture) &&
            (identical(other.allowShowPassword, allowShowPassword) ||
                other.allowShowPassword == allowShowPassword) &&
            (identical(other.allowShowPrivateKey, allowShowPrivateKey) ||
                other.allowShowPrivateKey == allowShowPrivateKey));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      biometricUnlock,
      requireAuthOnLaunch,
      requireAuthOnResume,
      authTimeout,
      clipboardClearTimeout,
      allowScreenCapture,
      allowShowPassword,
      allowShowPrivateKey);

  /// Create a copy of SecuritySettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SecuritySettingsImplCopyWith<_$SecuritySettingsImpl> get copyWith =>
      __$$SecuritySettingsImplCopyWithImpl<_$SecuritySettingsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SecuritySettingsImplToJson(
      this,
    );
  }
}

abstract class _SecuritySettings extends SecuritySettings {
  const factory _SecuritySettings(
      {final bool biometricUnlock,
      final bool requireAuthOnLaunch,
      final bool requireAuthOnResume,
      final int authTimeout,
      final int clipboardClearTimeout,
      final bool allowScreenCapture,
      final bool allowShowPassword,
      final bool allowShowPrivateKey}) = _$SecuritySettingsImpl;
  const _SecuritySettings._() : super._();

  factory _SecuritySettings.fromJson(Map<String, dynamic> json) =
      _$SecuritySettingsImpl.fromJson;

  /// 生体認証でロック解除
  @override
  bool get biometricUnlock;

  /// アプリ起動時に認証を要求
  @override
  bool get requireAuthOnLaunch;

  /// バックグラウンド時に認証を要求
  @override
  bool get requireAuthOnResume;

  /// 認証タイムアウト（秒）
  @override
  int get authTimeout;

  /// クリップボード自動クリア（秒、0で無効）
  @override
  int get clipboardClearTimeout;

  /// 画面キャプチャを許可
  @override
  bool get allowScreenCapture;

  /// パスワード表示を許可
  @override
  bool get allowShowPassword;

  /// 秘密鍵表示を許可
  @override
  bool get allowShowPrivateKey;

  /// Create a copy of SecuritySettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SecuritySettingsImplCopyWith<_$SecuritySettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
