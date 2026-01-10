// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tmux.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TmuxSession _$TmuxSessionFromJson(Map<String, dynamic> json) {
  return _TmuxSession.fromJson(json);
}

/// @nodoc
mixin _$TmuxSession {
  String get name => throw _privateConstructorUsedError;
  DateTime get created => throw _privateConstructorUsedError;
  bool get attached => throw _privateConstructorUsedError;
  int get windowCount => throw _privateConstructorUsedError;
  List<TmuxWindow> get windows => throw _privateConstructorUsedError;

  /// Serializes this TmuxSession to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TmuxSession
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TmuxSessionCopyWith<TmuxSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TmuxSessionCopyWith<$Res> {
  factory $TmuxSessionCopyWith(
          TmuxSession value, $Res Function(TmuxSession) then) =
      _$TmuxSessionCopyWithImpl<$Res, TmuxSession>;
  @useResult
  $Res call(
      {String name,
      DateTime created,
      bool attached,
      int windowCount,
      List<TmuxWindow> windows});
}

/// @nodoc
class _$TmuxSessionCopyWithImpl<$Res, $Val extends TmuxSession>
    implements $TmuxSessionCopyWith<$Res> {
  _$TmuxSessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TmuxSession
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? created = null,
    Object? attached = null,
    Object? windowCount = null,
    Object? windows = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      created: null == created
          ? _value.created
          : created // ignore: cast_nullable_to_non_nullable
              as DateTime,
      attached: null == attached
          ? _value.attached
          : attached // ignore: cast_nullable_to_non_nullable
              as bool,
      windowCount: null == windowCount
          ? _value.windowCount
          : windowCount // ignore: cast_nullable_to_non_nullable
              as int,
      windows: null == windows
          ? _value.windows
          : windows // ignore: cast_nullable_to_non_nullable
              as List<TmuxWindow>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TmuxSessionImplCopyWith<$Res>
    implements $TmuxSessionCopyWith<$Res> {
  factory _$$TmuxSessionImplCopyWith(
          _$TmuxSessionImpl value, $Res Function(_$TmuxSessionImpl) then) =
      __$$TmuxSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      DateTime created,
      bool attached,
      int windowCount,
      List<TmuxWindow> windows});
}

/// @nodoc
class __$$TmuxSessionImplCopyWithImpl<$Res>
    extends _$TmuxSessionCopyWithImpl<$Res, _$TmuxSessionImpl>
    implements _$$TmuxSessionImplCopyWith<$Res> {
  __$$TmuxSessionImplCopyWithImpl(
      _$TmuxSessionImpl _value, $Res Function(_$TmuxSessionImpl) _then)
      : super(_value, _then);

  /// Create a copy of TmuxSession
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? created = null,
    Object? attached = null,
    Object? windowCount = null,
    Object? windows = null,
  }) {
    return _then(_$TmuxSessionImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      created: null == created
          ? _value.created
          : created // ignore: cast_nullable_to_non_nullable
              as DateTime,
      attached: null == attached
          ? _value.attached
          : attached // ignore: cast_nullable_to_non_nullable
              as bool,
      windowCount: null == windowCount
          ? _value.windowCount
          : windowCount // ignore: cast_nullable_to_non_nullable
              as int,
      windows: null == windows
          ? _value._windows
          : windows // ignore: cast_nullable_to_non_nullable
              as List<TmuxWindow>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TmuxSessionImpl implements _TmuxSession {
  const _$TmuxSessionImpl(
      {required this.name,
      required this.created,
      required this.attached,
      required this.windowCount,
      final List<TmuxWindow> windows = const []})
      : _windows = windows;

  factory _$TmuxSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$TmuxSessionImplFromJson(json);

  @override
  final String name;
  @override
  final DateTime created;
  @override
  final bool attached;
  @override
  final int windowCount;
  final List<TmuxWindow> _windows;
  @override
  @JsonKey()
  List<TmuxWindow> get windows {
    if (_windows is EqualUnmodifiableListView) return _windows;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_windows);
  }

  @override
  String toString() {
    return 'TmuxSession(name: $name, created: $created, attached: $attached, windowCount: $windowCount, windows: $windows)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TmuxSessionImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.created, created) || other.created == created) &&
            (identical(other.attached, attached) ||
                other.attached == attached) &&
            (identical(other.windowCount, windowCount) ||
                other.windowCount == windowCount) &&
            const DeepCollectionEquality().equals(other._windows, _windows));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name, created, attached,
      windowCount, const DeepCollectionEquality().hash(_windows));

  /// Create a copy of TmuxSession
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TmuxSessionImplCopyWith<_$TmuxSessionImpl> get copyWith =>
      __$$TmuxSessionImplCopyWithImpl<_$TmuxSessionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TmuxSessionImplToJson(
      this,
    );
  }
}

abstract class _TmuxSession implements TmuxSession {
  const factory _TmuxSession(
      {required final String name,
      required final DateTime created,
      required final bool attached,
      required final int windowCount,
      final List<TmuxWindow> windows}) = _$TmuxSessionImpl;

  factory _TmuxSession.fromJson(Map<String, dynamic> json) =
      _$TmuxSessionImpl.fromJson;

  @override
  String get name;
  @override
  DateTime get created;
  @override
  bool get attached;
  @override
  int get windowCount;
  @override
  List<TmuxWindow> get windows;

  /// Create a copy of TmuxSession
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TmuxSessionImplCopyWith<_$TmuxSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TmuxWindow _$TmuxWindowFromJson(Map<String, dynamic> json) {
  return _TmuxWindow.fromJson(json);
}

/// @nodoc
mixin _$TmuxWindow {
  int get index => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  bool get active => throw _privateConstructorUsedError;
  int get paneCount => throw _privateConstructorUsedError;
  List<TmuxPane> get panes => throw _privateConstructorUsedError;

  /// Serializes this TmuxWindow to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TmuxWindow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TmuxWindowCopyWith<TmuxWindow> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TmuxWindowCopyWith<$Res> {
  factory $TmuxWindowCopyWith(
          TmuxWindow value, $Res Function(TmuxWindow) then) =
      _$TmuxWindowCopyWithImpl<$Res, TmuxWindow>;
  @useResult
  $Res call(
      {int index,
      String name,
      bool active,
      int paneCount,
      List<TmuxPane> panes});
}

/// @nodoc
class _$TmuxWindowCopyWithImpl<$Res, $Val extends TmuxWindow>
    implements $TmuxWindowCopyWith<$Res> {
  _$TmuxWindowCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TmuxWindow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? name = null,
    Object? active = null,
    Object? paneCount = null,
    Object? panes = null,
  }) {
    return _then(_value.copyWith(
      index: null == index
          ? _value.index
          : index // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      active: null == active
          ? _value.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
      paneCount: null == paneCount
          ? _value.paneCount
          : paneCount // ignore: cast_nullable_to_non_nullable
              as int,
      panes: null == panes
          ? _value.panes
          : panes // ignore: cast_nullable_to_non_nullable
              as List<TmuxPane>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TmuxWindowImplCopyWith<$Res>
    implements $TmuxWindowCopyWith<$Res> {
  factory _$$TmuxWindowImplCopyWith(
          _$TmuxWindowImpl value, $Res Function(_$TmuxWindowImpl) then) =
      __$$TmuxWindowImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int index,
      String name,
      bool active,
      int paneCount,
      List<TmuxPane> panes});
}

/// @nodoc
class __$$TmuxWindowImplCopyWithImpl<$Res>
    extends _$TmuxWindowCopyWithImpl<$Res, _$TmuxWindowImpl>
    implements _$$TmuxWindowImplCopyWith<$Res> {
  __$$TmuxWindowImplCopyWithImpl(
      _$TmuxWindowImpl _value, $Res Function(_$TmuxWindowImpl) _then)
      : super(_value, _then);

  /// Create a copy of TmuxWindow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? name = null,
    Object? active = null,
    Object? paneCount = null,
    Object? panes = null,
  }) {
    return _then(_$TmuxWindowImpl(
      index: null == index
          ? _value.index
          : index // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      active: null == active
          ? _value.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
      paneCount: null == paneCount
          ? _value.paneCount
          : paneCount // ignore: cast_nullable_to_non_nullable
              as int,
      panes: null == panes
          ? _value._panes
          : panes // ignore: cast_nullable_to_non_nullable
              as List<TmuxPane>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TmuxWindowImpl implements _TmuxWindow {
  const _$TmuxWindowImpl(
      {required this.index,
      required this.name,
      required this.active,
      required this.paneCount,
      final List<TmuxPane> panes = const []})
      : _panes = panes;

  factory _$TmuxWindowImpl.fromJson(Map<String, dynamic> json) =>
      _$$TmuxWindowImplFromJson(json);

  @override
  final int index;
  @override
  final String name;
  @override
  final bool active;
  @override
  final int paneCount;
  final List<TmuxPane> _panes;
  @override
  @JsonKey()
  List<TmuxPane> get panes {
    if (_panes is EqualUnmodifiableListView) return _panes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_panes);
  }

  @override
  String toString() {
    return 'TmuxWindow(index: $index, name: $name, active: $active, paneCount: $paneCount, panes: $panes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TmuxWindowImpl &&
            (identical(other.index, index) || other.index == index) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.active, active) || other.active == active) &&
            (identical(other.paneCount, paneCount) ||
                other.paneCount == paneCount) &&
            const DeepCollectionEquality().equals(other._panes, _panes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, index, name, active, paneCount,
      const DeepCollectionEquality().hash(_panes));

  /// Create a copy of TmuxWindow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TmuxWindowImplCopyWith<_$TmuxWindowImpl> get copyWith =>
      __$$TmuxWindowImplCopyWithImpl<_$TmuxWindowImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TmuxWindowImplToJson(
      this,
    );
  }
}

abstract class _TmuxWindow implements TmuxWindow {
  const factory _TmuxWindow(
      {required final int index,
      required final String name,
      required final bool active,
      required final int paneCount,
      final List<TmuxPane> panes}) = _$TmuxWindowImpl;

  factory _TmuxWindow.fromJson(Map<String, dynamic> json) =
      _$TmuxWindowImpl.fromJson;

  @override
  int get index;
  @override
  String get name;
  @override
  bool get active;
  @override
  int get paneCount;
  @override
  List<TmuxPane> get panes;

  /// Create a copy of TmuxWindow
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TmuxWindowImplCopyWith<_$TmuxWindowImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TmuxPane _$TmuxPaneFromJson(Map<String, dynamic> json) {
  return _TmuxPane.fromJson(json);
}

/// @nodoc
mixin _$TmuxPane {
  int get index => throw _privateConstructorUsedError;
  String get id => throw _privateConstructorUsedError;
  bool get active => throw _privateConstructorUsedError;
  String get currentCommand => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  int get width => throw _privateConstructorUsedError;
  int get height => throw _privateConstructorUsedError;
  int get cursorX => throw _privateConstructorUsedError;
  int get cursorY => throw _privateConstructorUsedError;

  /// Serializes this TmuxPane to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TmuxPane
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TmuxPaneCopyWith<TmuxPane> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TmuxPaneCopyWith<$Res> {
  factory $TmuxPaneCopyWith(TmuxPane value, $Res Function(TmuxPane) then) =
      _$TmuxPaneCopyWithImpl<$Res, TmuxPane>;
  @useResult
  $Res call(
      {int index,
      String id,
      bool active,
      String currentCommand,
      String title,
      int width,
      int height,
      int cursorX,
      int cursorY});
}

/// @nodoc
class _$TmuxPaneCopyWithImpl<$Res, $Val extends TmuxPane>
    implements $TmuxPaneCopyWith<$Res> {
  _$TmuxPaneCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TmuxPane
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? id = null,
    Object? active = null,
    Object? currentCommand = null,
    Object? title = null,
    Object? width = null,
    Object? height = null,
    Object? cursorX = null,
    Object? cursorY = null,
  }) {
    return _then(_value.copyWith(
      index: null == index
          ? _value.index
          : index // ignore: cast_nullable_to_non_nullable
              as int,
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      active: null == active
          ? _value.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
      currentCommand: null == currentCommand
          ? _value.currentCommand
          : currentCommand // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as int,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int,
      cursorX: null == cursorX
          ? _value.cursorX
          : cursorX // ignore: cast_nullable_to_non_nullable
              as int,
      cursorY: null == cursorY
          ? _value.cursorY
          : cursorY // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TmuxPaneImplCopyWith<$Res>
    implements $TmuxPaneCopyWith<$Res> {
  factory _$$TmuxPaneImplCopyWith(
          _$TmuxPaneImpl value, $Res Function(_$TmuxPaneImpl) then) =
      __$$TmuxPaneImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int index,
      String id,
      bool active,
      String currentCommand,
      String title,
      int width,
      int height,
      int cursorX,
      int cursorY});
}

/// @nodoc
class __$$TmuxPaneImplCopyWithImpl<$Res>
    extends _$TmuxPaneCopyWithImpl<$Res, _$TmuxPaneImpl>
    implements _$$TmuxPaneImplCopyWith<$Res> {
  __$$TmuxPaneImplCopyWithImpl(
      _$TmuxPaneImpl _value, $Res Function(_$TmuxPaneImpl) _then)
      : super(_value, _then);

  /// Create a copy of TmuxPane
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? id = null,
    Object? active = null,
    Object? currentCommand = null,
    Object? title = null,
    Object? width = null,
    Object? height = null,
    Object? cursorX = null,
    Object? cursorY = null,
  }) {
    return _then(_$TmuxPaneImpl(
      index: null == index
          ? _value.index
          : index // ignore: cast_nullable_to_non_nullable
              as int,
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      active: null == active
          ? _value.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
      currentCommand: null == currentCommand
          ? _value.currentCommand
          : currentCommand // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as int,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as int,
      cursorX: null == cursorX
          ? _value.cursorX
          : cursorX // ignore: cast_nullable_to_non_nullable
              as int,
      cursorY: null == cursorY
          ? _value.cursorY
          : cursorY // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TmuxPaneImpl implements _TmuxPane {
  const _$TmuxPaneImpl(
      {required this.index,
      required this.id,
      required this.active,
      required this.currentCommand,
      required this.title,
      required this.width,
      required this.height,
      required this.cursorX,
      required this.cursorY});

  factory _$TmuxPaneImpl.fromJson(Map<String, dynamic> json) =>
      _$$TmuxPaneImplFromJson(json);

  @override
  final int index;
  @override
  final String id;
  @override
  final bool active;
  @override
  final String currentCommand;
  @override
  final String title;
  @override
  final int width;
  @override
  final int height;
  @override
  final int cursorX;
  @override
  final int cursorY;

  @override
  String toString() {
    return 'TmuxPane(index: $index, id: $id, active: $active, currentCommand: $currentCommand, title: $title, width: $width, height: $height, cursorX: $cursorX, cursorY: $cursorY)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TmuxPaneImpl &&
            (identical(other.index, index) || other.index == index) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.active, active) || other.active == active) &&
            (identical(other.currentCommand, currentCommand) ||
                other.currentCommand == currentCommand) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.cursorX, cursorX) || other.cursorX == cursorX) &&
            (identical(other.cursorY, cursorY) || other.cursorY == cursorY));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, index, id, active,
      currentCommand, title, width, height, cursorX, cursorY);

  /// Create a copy of TmuxPane
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TmuxPaneImplCopyWith<_$TmuxPaneImpl> get copyWith =>
      __$$TmuxPaneImplCopyWithImpl<_$TmuxPaneImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TmuxPaneImplToJson(
      this,
    );
  }
}

abstract class _TmuxPane implements TmuxPane {
  const factory _TmuxPane(
      {required final int index,
      required final String id,
      required final bool active,
      required final String currentCommand,
      required final String title,
      required final int width,
      required final int height,
      required final int cursorX,
      required final int cursorY}) = _$TmuxPaneImpl;

  factory _TmuxPane.fromJson(Map<String, dynamic> json) =
      _$TmuxPaneImpl.fromJson;

  @override
  int get index;
  @override
  String get id;
  @override
  bool get active;
  @override
  String get currentCommand;
  @override
  String get title;
  @override
  int get width;
  @override
  int get height;
  @override
  int get cursorX;
  @override
  int get cursorY;

  /// Create a copy of TmuxPane
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TmuxPaneImplCopyWith<_$TmuxPaneImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
