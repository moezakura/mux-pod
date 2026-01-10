// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppSettingsImpl _$$AppSettingsImplFromJson(Map<String, dynamic> json) =>
    _$AppSettingsImpl(
      display: json['display'] == null
          ? const DisplaySettings()
          : DisplaySettings.fromJson(json['display'] as Map<String, dynamic>),
      terminal: json['terminal'] == null
          ? const TerminalSettings()
          : TerminalSettings.fromJson(json['terminal'] as Map<String, dynamic>),
      ssh: json['ssh'] == null
          ? const SshSettings()
          : SshSettings.fromJson(json['ssh'] as Map<String, dynamic>),
      security: json['security'] == null
          ? const SecuritySettings()
          : SecuritySettings.fromJson(json['security'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$AppSettingsImplToJson(_$AppSettingsImpl instance) =>
    <String, dynamic>{
      'display': instance.display,
      'terminal': instance.terminal,
      'ssh': instance.ssh,
      'security': instance.security,
    };

_$DisplaySettingsImpl _$$DisplaySettingsImplFromJson(
        Map<String, dynamic> json) =>
    _$DisplaySettingsImpl(
      darkMode: json['darkMode'] as bool? ?? true,
      useSystemTheme: json['useSystemTheme'] as bool? ?? true,
      lockOrientation: json['lockOrientation'] as bool? ?? false,
      keepScreenOn: json['keepScreenOn'] as bool? ?? true,
      fullScreen: json['fullScreen'] as bool? ?? false,
      showStatusBar: json['showStatusBar'] as bool? ?? true,
    );

Map<String, dynamic> _$$DisplaySettingsImplToJson(
        _$DisplaySettingsImpl instance) =>
    <String, dynamic>{
      'darkMode': instance.darkMode,
      'useSystemTheme': instance.useSystemTheme,
      'lockOrientation': instance.lockOrientation,
      'keepScreenOn': instance.keepScreenOn,
      'fullScreen': instance.fullScreen,
      'showStatusBar': instance.showStatusBar,
    };

_$TerminalSettingsImpl _$$TerminalSettingsImplFromJson(
        Map<String, dynamic> json) =>
    _$TerminalSettingsImpl(
      fontFamily:
          $enumDecodeNullable(_$FontFamilyEnumMap, json['fontFamily']) ??
              FontFamily.jetBrainsMono,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      colorTheme:
          $enumDecodeNullable(_$ColorThemeEnumMap, json['colorTheme']) ??
              ColorTheme.dracula,
      cursorBlink: json['cursorBlink'] as bool? ?? true,
      cursorStyle: json['cursorStyle'] as String? ?? 'block',
      scrollbackLines: (json['scrollbackLines'] as num?)?.toInt() ?? 10000,
      bellSound: json['bellSound'] as bool? ?? true,
      bellVibrate: json['bellVibrate'] as bool? ?? true,
      showSpecialKeysBar: json['showSpecialKeysBar'] as bool? ?? true,
      autoClearSelection: json['autoClearSelection'] as bool? ?? true,
      doubleTapSelectWord: json['doubleTapSelectWord'] as bool? ?? true,
      tripleTapSelectLine: json['tripleTapSelectLine'] as bool? ?? true,
      longPressContextMenu: json['longPressContextMenu'] as bool? ?? true,
      pinchToZoom: json['pinchToZoom'] as bool? ?? true,
      minFontSize: (json['minFontSize'] as num?)?.toDouble() ?? 8.0,
      maxFontSize: (json['maxFontSize'] as num?)?.toDouble() ?? 32.0,
    );

Map<String, dynamic> _$$TerminalSettingsImplToJson(
        _$TerminalSettingsImpl instance) =>
    <String, dynamic>{
      'fontFamily': _$FontFamilyEnumMap[instance.fontFamily]!,
      'fontSize': instance.fontSize,
      'lineHeight': instance.lineHeight,
      'colorTheme': _$ColorThemeEnumMap[instance.colorTheme]!,
      'cursorBlink': instance.cursorBlink,
      'cursorStyle': instance.cursorStyle,
      'scrollbackLines': instance.scrollbackLines,
      'bellSound': instance.bellSound,
      'bellVibrate': instance.bellVibrate,
      'showSpecialKeysBar': instance.showSpecialKeysBar,
      'autoClearSelection': instance.autoClearSelection,
      'doubleTapSelectWord': instance.doubleTapSelectWord,
      'tripleTapSelectLine': instance.tripleTapSelectLine,
      'longPressContextMenu': instance.longPressContextMenu,
      'pinchToZoom': instance.pinchToZoom,
      'minFontSize': instance.minFontSize,
      'maxFontSize': instance.maxFontSize,
    };

const _$FontFamilyEnumMap = {
  FontFamily.jetBrainsMono: 'jetBrainsMono',
  FontFamily.firaCode: 'firaCode',
  FontFamily.meslo: 'meslo',
  FontFamily.hackGen: 'hackGen',
  FontFamily.plemolJP: 'plemolJP',
};

const _$ColorThemeEnumMap = {
  ColorTheme.dracula: 'dracula',
  ColorTheme.solarized: 'solarized',
  ColorTheme.monokai: 'monokai',
  ColorTheme.nord: 'nord',
  ColorTheme.custom: 'custom',
};

_$SshSettingsImpl _$$SshSettingsImplFromJson(Map<String, dynamic> json) =>
    _$SshSettingsImpl(
      connectionTimeout: (json['connectionTimeout'] as num?)?.toInt() ?? 30,
      keepAliveInterval: (json['keepAliveInterval'] as num?)?.toInt() ?? 60,
      reconnectAttempts: (json['reconnectAttempts'] as num?)?.toInt() ?? 3,
      reconnectDelay: (json['reconnectDelay'] as num?)?.toInt() ?? 5,
      compression: json['compression'] as bool? ?? false,
      defaultPtyWidth: (json['defaultPtyWidth'] as num?)?.toInt() ?? 80,
      defaultPtyHeight: (json['defaultPtyHeight'] as num?)?.toInt() ?? 24,
      defaultTerm: json['defaultTerm'] as String? ?? 'xterm-256color',
    );

Map<String, dynamic> _$$SshSettingsImplToJson(_$SshSettingsImpl instance) =>
    <String, dynamic>{
      'connectionTimeout': instance.connectionTimeout,
      'keepAliveInterval': instance.keepAliveInterval,
      'reconnectAttempts': instance.reconnectAttempts,
      'reconnectDelay': instance.reconnectDelay,
      'compression': instance.compression,
      'defaultPtyWidth': instance.defaultPtyWidth,
      'defaultPtyHeight': instance.defaultPtyHeight,
      'defaultTerm': instance.defaultTerm,
    };

_$SecuritySettingsImpl _$$SecuritySettingsImplFromJson(
        Map<String, dynamic> json) =>
    _$SecuritySettingsImpl(
      biometricUnlock: json['biometricUnlock'] as bool? ?? false,
      requireAuthOnLaunch: json['requireAuthOnLaunch'] as bool? ?? false,
      requireAuthOnResume: json['requireAuthOnResume'] as bool? ?? false,
      authTimeout: (json['authTimeout'] as num?)?.toInt() ?? 300,
      clipboardClearTimeout:
          (json['clipboardClearTimeout'] as num?)?.toInt() ?? 60,
      allowScreenCapture: json['allowScreenCapture'] as bool? ?? true,
      allowShowPassword: json['allowShowPassword'] as bool? ?? false,
      allowShowPrivateKey: json['allowShowPrivateKey'] as bool? ?? false,
    );

Map<String, dynamic> _$$SecuritySettingsImplToJson(
        _$SecuritySettingsImpl instance) =>
    <String, dynamic>{
      'biometricUnlock': instance.biometricUnlock,
      'requireAuthOnLaunch': instance.requireAuthOnLaunch,
      'requireAuthOnResume': instance.requireAuthOnResume,
      'authTimeout': instance.authTimeout,
      'clipboardClearTimeout': instance.clipboardClearTimeout,
      'allowScreenCapture': instance.allowScreenCapture,
      'allowShowPassword': instance.allowShowPassword,
      'allowShowPrivateKey': instance.allowShowPrivateKey,
    };
