// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connect_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ConnectRequest> _$connectRequestSerializer =
    new _$ConnectRequestSerializer();

class _$ConnectRequestSerializer
    implements StructuredSerializer<ConnectRequest> {
  @override
  final Iterable<Type> types = const [ConnectRequest, _$ConnectRequest];
  @override
  final String wireName = 'ConnectRequest';

  @override
  Iterable<Object?> serialize(Serializers serializers, ConnectRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'appName',
      serializers.serialize(object.appName,
          specifiedType: const FullType(String)),
      'appId',
      serializers.serialize(object.appId,
          specifiedType: const FullType(String)),
      'instanceId',
      serializers.serialize(object.instanceId,
          specifiedType: const FullType(String)),
      'entrypoints',
      serializers.serialize(object.entrypoints,
          specifiedType:
              const FullType(BuiltList, const [const FullType(String)])),
    ];

    return result;
  }

  @override
  ConnectRequest deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ConnectRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'appName':
          result.appName = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'appId':
          result.appId = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'instanceId':
          result.instanceId = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'entrypoints':
          result.entrypoints.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(String)]))!
              as BuiltList<Object?>);
          break;
      }
    }

    return result.build();
  }
}

class _$ConnectRequest extends ConnectRequest {
  @override
  final String appName;
  @override
  final String appId;
  @override
  final String instanceId;
  @override
  final BuiltList<String> entrypoints;

  factory _$ConnectRequest([void Function(ConnectRequestBuilder)? updates]) =>
      (new ConnectRequestBuilder()..update(updates))._build();

  _$ConnectRequest._(
      {required this.appName,
      required this.appId,
      required this.instanceId,
      required this.entrypoints})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        appName, r'ConnectRequest', 'appName');
    BuiltValueNullFieldError.checkNotNull(appId, r'ConnectRequest', 'appId');
    BuiltValueNullFieldError.checkNotNull(
        instanceId, r'ConnectRequest', 'instanceId');
    BuiltValueNullFieldError.checkNotNull(
        entrypoints, r'ConnectRequest', 'entrypoints');
  }

  @override
  ConnectRequest rebuild(void Function(ConnectRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ConnectRequestBuilder toBuilder() =>
      new ConnectRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ConnectRequest &&
        appName == other.appName &&
        appId == other.appId &&
        instanceId == other.instanceId &&
        entrypoints == other.entrypoints;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appName.hashCode);
    _$hash = $jc(_$hash, appId.hashCode);
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, entrypoints.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ConnectRequest')
          ..add('appName', appName)
          ..add('appId', appId)
          ..add('instanceId', instanceId)
          ..add('entrypoints', entrypoints))
        .toString();
  }
}

class ConnectRequestBuilder
    implements Builder<ConnectRequest, ConnectRequestBuilder> {
  _$ConnectRequest? _$v;

  String? _appName;
  String? get appName => _$this._appName;
  set appName(String? appName) => _$this._appName = appName;

  String? _appId;
  String? get appId => _$this._appId;
  set appId(String? appId) => _$this._appId = appId;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  ListBuilder<String>? _entrypoints;
  ListBuilder<String> get entrypoints =>
      _$this._entrypoints ??= new ListBuilder<String>();
  set entrypoints(ListBuilder<String>? entrypoints) =>
      _$this._entrypoints = entrypoints;

  ConnectRequestBuilder();

  ConnectRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appName = $v.appName;
      _appId = $v.appId;
      _instanceId = $v.instanceId;
      _entrypoints = $v.entrypoints.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ConnectRequest other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$ConnectRequest;
  }

  @override
  void update(void Function(ConnectRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ConnectRequest build() => _build();

  _$ConnectRequest _build() {
    _$ConnectRequest _$result;
    try {
      _$result = _$v ??
          new _$ConnectRequest._(
              appName: BuiltValueNullFieldError.checkNotNull(
                  appName, r'ConnectRequest', 'appName'),
              appId: BuiltValueNullFieldError.checkNotNull(
                  appId, r'ConnectRequest', 'appId'),
              instanceId: BuiltValueNullFieldError.checkNotNull(
                  instanceId, r'ConnectRequest', 'instanceId'),
              entrypoints: entrypoints.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entrypoints';
        entrypoints.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            r'ConnectRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
