// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_types.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ConnectFailure> _$connectFailureSerializer =
    new _$ConnectFailureSerializer();
Serializer<DevToolsOpener> _$devToolsOpenerSerializer =
    new _$DevToolsOpenerSerializer();
Serializer<DevToolsUrl> _$devToolsUrlSerializer = new _$DevToolsUrlSerializer();
Serializer<DebugStateChange> _$debugStateChangeSerializer =
    new _$DebugStateChangeSerializer();

class _$ConnectFailureSerializer
    implements StructuredSerializer<ConnectFailure> {
  @override
  final Iterable<Type> types = const [ConnectFailure, _$ConnectFailure];
  @override
  final String wireName = 'ConnectFailure';

  @override
  Iterable<Object?> serialize(Serializers serializers, ConnectFailure object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'tabId',
      serializers.serialize(object.tabId, specifiedType: const FullType(int)),
    ];
    Object? value;
    value = object.reason;
    if (value != null) {
      result
        ..add('reason')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  ConnectFailure deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ConnectFailureBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'tabId':
          result.tabId = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
        case 'reason':
          result.reason = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$DevToolsOpenerSerializer
    implements StructuredSerializer<DevToolsOpener> {
  @override
  final Iterable<Type> types = const [DevToolsOpener, _$DevToolsOpener];
  @override
  final String wireName = 'DevToolsOpener';

  @override
  Iterable<Object?> serialize(Serializers serializers, DevToolsOpener object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'newWindow',
      serializers.serialize(object.newWindow,
          specifiedType: const FullType(bool)),
    ];

    return result;
  }

  @override
  DevToolsOpener deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DevToolsOpenerBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'newWindow':
          result.newWindow = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$DevToolsUrlSerializer implements StructuredSerializer<DevToolsUrl> {
  @override
  final Iterable<Type> types = const [DevToolsUrl, _$DevToolsUrl];
  @override
  final String wireName = 'DevToolsUrl';

  @override
  Iterable<Object?> serialize(Serializers serializers, DevToolsUrl object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'tabId',
      serializers.serialize(object.tabId, specifiedType: const FullType(int)),
      'url',
      serializers.serialize(object.url, specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  DevToolsUrl deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DevToolsUrlBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'tabId':
          result.tabId = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
        case 'url':
          result.url = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
      }
    }

    return result.build();
  }
}

class _$DebugStateChangeSerializer
    implements StructuredSerializer<DebugStateChange> {
  @override
  final Iterable<Type> types = const [DebugStateChange, _$DebugStateChange];
  @override
  final String wireName = 'DebugStateChange';

  @override
  Iterable<Object?> serialize(Serializers serializers, DebugStateChange object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'tabId',
      serializers.serialize(object.tabId, specifiedType: const FullType(int)),
      'newState',
      serializers.serialize(object.newState,
          specifiedType: const FullType(String)),
    ];
    Object? value;
    value = object.reason;
    if (value != null) {
      result
        ..add('reason')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  DebugStateChange deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DebugStateChangeBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'tabId':
          result.tabId = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
        case 'newState':
          result.newState = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'reason':
          result.reason = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$ConnectFailure extends ConnectFailure {
  @override
  final int tabId;
  @override
  final String? reason;

  factory _$ConnectFailure([void Function(ConnectFailureBuilder)? updates]) =>
      (new ConnectFailureBuilder()..update(updates))._build();

  _$ConnectFailure._({required this.tabId, this.reason}) : super._() {
    BuiltValueNullFieldError.checkNotNull(tabId, r'ConnectFailure', 'tabId');
  }

  @override
  ConnectFailure rebuild(void Function(ConnectFailureBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ConnectFailureBuilder toBuilder() =>
      new ConnectFailureBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ConnectFailure &&
        tabId == other.tabId &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, tabId.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ConnectFailure')
          ..add('tabId', tabId)
          ..add('reason', reason))
        .toString();
  }
}

class ConnectFailureBuilder
    implements Builder<ConnectFailure, ConnectFailureBuilder> {
  _$ConnectFailure? _$v;

  int? _tabId;
  int? get tabId => _$this._tabId;
  set tabId(int? tabId) => _$this._tabId = tabId;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  ConnectFailureBuilder();

  ConnectFailureBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _tabId = $v.tabId;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ConnectFailure other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ConnectFailure;
  }

  @override
  void update(void Function(ConnectFailureBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ConnectFailure build() => _build();

  _$ConnectFailure _build() {
    final _$result = _$v ??
        new _$ConnectFailure._(
            tabId: BuiltValueNullFieldError.checkNotNull(
                tabId, r'ConnectFailure', 'tabId'),
            reason: reason);
    replace(_$result);
    return _$result;
  }
}

class _$DevToolsOpener extends DevToolsOpener {
  @override
  final bool newWindow;

  factory _$DevToolsOpener([void Function(DevToolsOpenerBuilder)? updates]) =>
      (new DevToolsOpenerBuilder()..update(updates))._build();

  _$DevToolsOpener._({required this.newWindow}) : super._() {
    BuiltValueNullFieldError.checkNotNull(
        newWindow, r'DevToolsOpener', 'newWindow');
  }

  @override
  DevToolsOpener rebuild(void Function(DevToolsOpenerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DevToolsOpenerBuilder toBuilder() =>
      new DevToolsOpenerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DevToolsOpener && newWindow == other.newWindow;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, newWindow.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DevToolsOpener')
          ..add('newWindow', newWindow))
        .toString();
  }
}

class DevToolsOpenerBuilder
    implements Builder<DevToolsOpener, DevToolsOpenerBuilder> {
  _$DevToolsOpener? _$v;

  bool? _newWindow;
  bool? get newWindow => _$this._newWindow;
  set newWindow(bool? newWindow) => _$this._newWindow = newWindow;

  DevToolsOpenerBuilder();

  DevToolsOpenerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _newWindow = $v.newWindow;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DevToolsOpener other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DevToolsOpener;
  }

  @override
  void update(void Function(DevToolsOpenerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DevToolsOpener build() => _build();

  _$DevToolsOpener _build() {
    final _$result = _$v ??
        new _$DevToolsOpener._(
            newWindow: BuiltValueNullFieldError.checkNotNull(
                newWindow, r'DevToolsOpener', 'newWindow'));
    replace(_$result);
    return _$result;
  }
}

class _$DevToolsUrl extends DevToolsUrl {
  @override
  final int tabId;
  @override
  final String url;

  factory _$DevToolsUrl([void Function(DevToolsUrlBuilder)? updates]) =>
      (new DevToolsUrlBuilder()..update(updates))._build();

  _$DevToolsUrl._({required this.tabId, required this.url}) : super._() {
    BuiltValueNullFieldError.checkNotNull(tabId, r'DevToolsUrl', 'tabId');
    BuiltValueNullFieldError.checkNotNull(url, r'DevToolsUrl', 'url');
  }

  @override
  DevToolsUrl rebuild(void Function(DevToolsUrlBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DevToolsUrlBuilder toBuilder() => new DevToolsUrlBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DevToolsUrl && tabId == other.tabId && url == other.url;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, tabId.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DevToolsUrl')
          ..add('tabId', tabId)
          ..add('url', url))
        .toString();
  }
}

class DevToolsUrlBuilder implements Builder<DevToolsUrl, DevToolsUrlBuilder> {
  _$DevToolsUrl? _$v;

  int? _tabId;
  int? get tabId => _$this._tabId;
  set tabId(int? tabId) => _$this._tabId = tabId;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  DevToolsUrlBuilder();

  DevToolsUrlBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _tabId = $v.tabId;
      _url = $v.url;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DevToolsUrl other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DevToolsUrl;
  }

  @override
  void update(void Function(DevToolsUrlBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DevToolsUrl build() => _build();

  _$DevToolsUrl _build() {
    final _$result = _$v ??
        new _$DevToolsUrl._(
            tabId: BuiltValueNullFieldError.checkNotNull(
                tabId, r'DevToolsUrl', 'tabId'),
            url: BuiltValueNullFieldError.checkNotNull(
                url, r'DevToolsUrl', 'url'));
    replace(_$result);
    return _$result;
  }
}

class _$DebugStateChange extends DebugStateChange {
  @override
  final int tabId;
  @override
  final String newState;
  @override
  final String? reason;

  factory _$DebugStateChange(
          [void Function(DebugStateChangeBuilder)? updates]) =>
      (new DebugStateChangeBuilder()..update(updates))._build();

  _$DebugStateChange._(
      {required this.tabId, required this.newState, this.reason})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(tabId, r'DebugStateChange', 'tabId');
    BuiltValueNullFieldError.checkNotNull(
        newState, r'DebugStateChange', 'newState');
  }

  @override
  DebugStateChange rebuild(void Function(DebugStateChangeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DebugStateChangeBuilder toBuilder() =>
      new DebugStateChangeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DebugStateChange &&
        tabId == other.tabId &&
        newState == other.newState &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, tabId.hashCode);
    _$hash = $jc(_$hash, newState.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DebugStateChange')
          ..add('tabId', tabId)
          ..add('newState', newState)
          ..add('reason', reason))
        .toString();
  }
}

class DebugStateChangeBuilder
    implements Builder<DebugStateChange, DebugStateChangeBuilder> {
  _$DebugStateChange? _$v;

  int? _tabId;
  int? get tabId => _$this._tabId;
  set tabId(int? tabId) => _$this._tabId = tabId;

  String? _newState;
  String? get newState => _$this._newState;
  set newState(String? newState) => _$this._newState = newState;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  DebugStateChangeBuilder();

  DebugStateChangeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _tabId = $v.tabId;
      _newState = $v.newState;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DebugStateChange other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DebugStateChange;
  }

  @override
  void update(void Function(DebugStateChangeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DebugStateChange build() => _build();

  _$DebugStateChange _build() {
    final _$result = _$v ??
        new _$DebugStateChange._(
            tabId: BuiltValueNullFieldError.checkNotNull(
                tabId, r'DebugStateChange', 'tabId'),
            newState: BuiltValueNullFieldError.checkNotNull(
                newState, r'DebugStateChange', 'newState'),
            reason: reason);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
