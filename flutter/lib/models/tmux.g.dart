// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tmux.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TmuxSessionImpl _$$TmuxSessionImplFromJson(Map<String, dynamic> json) =>
    _$TmuxSessionImpl(
      name: json['name'] as String,
      created: DateTime.parse(json['created'] as String),
      attached: json['attached'] as bool,
      windowCount: (json['windowCount'] as num).toInt(),
      windows: (json['windows'] as List<dynamic>?)
              ?.map((e) => TmuxWindow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$TmuxSessionImplToJson(_$TmuxSessionImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'created': instance.created.toIso8601String(),
      'attached': instance.attached,
      'windowCount': instance.windowCount,
      'windows': instance.windows,
    };

_$TmuxWindowImpl _$$TmuxWindowImplFromJson(Map<String, dynamic> json) =>
    _$TmuxWindowImpl(
      index: (json['index'] as num).toInt(),
      name: json['name'] as String,
      active: json['active'] as bool,
      paneCount: (json['paneCount'] as num).toInt(),
      panes: (json['panes'] as List<dynamic>?)
              ?.map((e) => TmuxPane.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$TmuxWindowImplToJson(_$TmuxWindowImpl instance) =>
    <String, dynamic>{
      'index': instance.index,
      'name': instance.name,
      'active': instance.active,
      'paneCount': instance.paneCount,
      'panes': instance.panes,
    };

_$TmuxPaneImpl _$$TmuxPaneImplFromJson(Map<String, dynamic> json) =>
    _$TmuxPaneImpl(
      index: (json['index'] as num).toInt(),
      id: json['id'] as String,
      active: json['active'] as bool,
      currentCommand: json['currentCommand'] as String,
      title: json['title'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      cursorX: (json['cursorX'] as num).toInt(),
      cursorY: (json['cursorY'] as num).toInt(),
    );

Map<String, dynamic> _$$TmuxPaneImplToJson(_$TmuxPaneImpl instance) =>
    <String, dynamic>{
      'index': instance.index,
      'id': instance.id,
      'active': instance.active,
      'currentCommand': instance.currentCommand,
      'title': instance.title,
      'width': instance.width,
      'height': instance.height,
      'cursorX': instance.cursorX,
      'cursorY': instance.cursorY,
    };
