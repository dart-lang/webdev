// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_entrypoint_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<RegisterEntrypointRequest> _$registerEntrypointRequestSerializer =
    new _$RegisterEntrypointRequestSerializer();

class _$RegisterEntrypointRequestSerializer
    implements StructuredSerializer<RegisterEntrypointRequest> {
  @override
  final Iterable<Type> types = const [
    RegisterEntrypointRequest,
    _$RegisterEntrypointRequest
  ];
  @override
  final String wireName = 'RegisterEntrypointRequest';

  @override
  Iterable<Object?> serialize(
      Serializers serializers, RegisterEntrypointRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'appName',
      serializers.serialize(object.appName,
          specifiedType: const FullType(String)),
      'entrypointPath',
      serializers.serialize(object.entrypointPath,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  RegisterEntrypointRequest deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new RegisterEntrypointRequestBuilder();

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
        case 'entrypointPath':
          result.entrypointPath = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
      }
    }

    return result.build();
  }
}

class _$RegisterEntrypointRequest extends RegisterEntrypointRequest {
  @override
  final String appName;
  @override
  final String entrypointPath;

  factory _$RegisterEntrypointRequest(
          [void Function(RegisterEntrypointRequestBuilder)? updates]) =>
      (new RegisterEntrypointRequestBuilder()..update(updates))._build();

  _$RegisterEntrypointRequest._(
      {required this.appName, required this.entrypointPath})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(
        appName, r'RegisterEntrypointRequest', 'appName');
    BuiltValueNullFieldError.checkNotNull(
        entrypointPath, r'RegisterEntrypointRequest', 'entrypointPath');
  }

  @override
  RegisterEntrypointRequest rebuild(
          void Function(RegisterEntrypointRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegisterEntrypointRequestBuilder toBuilder() =>
      new RegisterEntrypointRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegisterEntrypointRequest &&
        appName == other.appName &&
        entrypointPath == other.entrypointPath;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appName.hashCode);
    _$hash = $jc(_$hash, entrypointPath.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegisterEntrypointRequest')
          ..add('appName', appName)
          ..add('entrypointPath', entrypointPath))
        .toString();
  }
}

class RegisterEntrypointRequestBuilder
    implements
        Builder<RegisterEntrypointRequest, RegisterEntrypointRequestBuilder> {
  _$RegisterEntrypointRequest? _$v;

  String? _appName;
  String? get appName => _$this._appName;
  set appName(String? appName) => _$this._appName = appName;

  String? _entrypointPath;
  String? get entrypointPath => _$this._entrypointPath;
  set entrypointPath(String? entrypointPath) =>
      _$this._entrypointPath = entrypointPath;

  RegisterEntrypointRequestBuilder();

  RegisterEntrypointRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appName = $v.appName;
      _entrypointPath = $v.entrypointPath;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegisterEntrypointRequest other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$RegisterEntrypointRequest;
  }

  @override
  void update(void Function(RegisterEntrypointRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegisterEntrypointRequest build() => _build();

  _$RegisterEntrypointRequest _build() {
    final _$result = _$v ??
        new _$RegisterEntrypointRequest._(
            appName: BuiltValueNullFieldError.checkNotNull(
                appName, r'RegisterEntrypointRequest', 'appName'),
            entrypointPath: BuiltValueNullFieldError.checkNotNull(
                entrypointPath,
                r'RegisterEntrypointRequest',
                'entrypointPath'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
