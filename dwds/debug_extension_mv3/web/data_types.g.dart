// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_types.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ConnectFailure> _$connectFailureSerializer =
    new _$ConnectFailureSerializer();
Serializer<DevToolsOpener> _$devToolsOpenerSerializer =
    new _$DevToolsOpenerSerializer();
Serializer<EncodedUri> _$encodedUriSerializer = new _$EncodedUriSerializer();
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

class _$EncodedUriSerializer implements StructuredSerializer<EncodedUri> {
  @override
  final Iterable<Type> types = const [EncodedUri, _$EncodedUri];
  @override
  final String wireName = 'EncodedUri';

  @override
  Iterable<Object?> serialize(Serializers serializers, EncodedUri object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'uri',
      serializers.serialize(object.uri, specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  EncodedUri deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new EncodedUriBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'uri':
          result.uri = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
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
    return $jf($jc($jc(0, tabId.hashCode), reason.hashCode));
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
    return $jf($jc(0, newWindow.hashCode));
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

class _$EncodedUri extends EncodedUri {
  @override
  final String uri;

  factory _$EncodedUri([void Function(EncodedUriBuilder)? updates]) =>
      (new EncodedUriBuilder()..update(updates))._build();

  _$EncodedUri._({required this.uri}) : super._() {
    BuiltValueNullFieldError.checkNotNull(uri, r'EncodedUri', 'uri');
  }

  @override
  EncodedUri rebuild(void Function(EncodedUriBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EncodedUriBuilder toBuilder() => new EncodedUriBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EncodedUri && uri == other.uri;
  }

  @override
  int get hashCode {
    return $jf($jc(0, uri.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EncodedUri')..add('uri', uri))
        .toString();
  }
}

class EncodedUriBuilder implements Builder<EncodedUri, EncodedUriBuilder> {
  _$EncodedUri? _$v;

  String? _uri;
  String? get uri => _$this._uri;
  set uri(String? uri) => _$this._uri = uri;

  EncodedUriBuilder();

  EncodedUriBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _uri = $v.uri;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EncodedUri other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$EncodedUri;
  }

  @override
  void update(void Function(EncodedUriBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EncodedUri build() => _build();

  _$EncodedUri _build() {
    final _$result = _$v ??
        new _$EncodedUri._(
            uri: BuiltValueNullFieldError.checkNotNull(
                uri, r'EncodedUri', 'uri'));
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
    return $jf($jc($jc(0, tabId.hashCode), url.hashCode));
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
    return $jf(
        $jc($jc($jc(0, tabId.hashCode), newState.hashCode), reason.hashCode));
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

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new,unnecessary_lambdas
