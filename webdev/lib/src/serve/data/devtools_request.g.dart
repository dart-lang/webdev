// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'devtools_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<DevToolsRequest> _$devToolsRequestSerializer =
    new _$DevToolsRequestSerializer();
Serializer<DevToolsResponse> _$devToolsResponseSerializer =
    new _$DevToolsResponseSerializer();

class _$DevToolsRequestSerializer
    implements StructuredSerializer<DevToolsRequest> {
  @override
  final Iterable<Type> types = const [DevToolsRequest, _$DevToolsRequest];
  @override
  final String wireName = 'DevToolsRequest';

  @override
  Iterable serialize(Serializers serializers, DevToolsRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'appId',
      serializers.serialize(object.appId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  DevToolsRequest deserialize(Serializers serializers, Iterable serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DevToolsRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'appId':
          result.appId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$DevToolsResponseSerializer
    implements StructuredSerializer<DevToolsResponse> {
  @override
  final Iterable<Type> types = const [DevToolsResponse, _$DevToolsResponse];
  @override
  final String wireName = 'DevToolsResponse';

  @override
  Iterable serialize(Serializers serializers, DevToolsResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'success',
      serializers.serialize(object.success,
          specifiedType: const FullType(bool)),
      'error',
      serializers.serialize(object.error,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  DevToolsResponse deserialize(Serializers serializers, Iterable serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DevToolsResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'success':
          result.success = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'error':
          result.error = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$DevToolsRequest extends DevToolsRequest {
  @override
  final String appId;

  factory _$DevToolsRequest([void updates(DevToolsRequestBuilder b)]) =>
      (new DevToolsRequestBuilder()..update(updates)).build();

  _$DevToolsRequest._({this.appId}) : super._() {
    if (appId == null) {
      throw new BuiltValueNullFieldError('DevToolsRequest', 'appId');
    }
  }

  @override
  DevToolsRequest rebuild(void updates(DevToolsRequestBuilder b)) =>
      (toBuilder()..update(updates)).build();

  @override
  DevToolsRequestBuilder toBuilder() =>
      new DevToolsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DevToolsRequest && appId == other.appId;
  }

  @override
  int get hashCode {
    return $jf($jc(0, appId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DevToolsRequest')..add('appId', appId))
        .toString();
  }
}

class DevToolsRequestBuilder
    implements Builder<DevToolsRequest, DevToolsRequestBuilder> {
  _$DevToolsRequest _$v;

  String _appId;
  String get appId => _$this._appId;
  set appId(String appId) => _$this._appId = appId;

  DevToolsRequestBuilder();

  DevToolsRequestBuilder get _$this {
    if (_$v != null) {
      _appId = _$v.appId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DevToolsRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$DevToolsRequest;
  }

  @override
  void update(void updates(DevToolsRequestBuilder b)) {
    if (updates != null) updates(this);
  }

  @override
  _$DevToolsRequest build() {
    final _$result = _$v ?? new _$DevToolsRequest._(appId: appId);
    replace(_$result);
    return _$result;
  }
}

class _$DevToolsResponse extends DevToolsResponse {
  @override
  final bool success;
  @override
  final String error;

  factory _$DevToolsResponse([void updates(DevToolsResponseBuilder b)]) =>
      (new DevToolsResponseBuilder()..update(updates)).build();

  _$DevToolsResponse._({this.success, this.error}) : super._() {
    if (success == null) {
      throw new BuiltValueNullFieldError('DevToolsResponse', 'success');
    }
    if (error == null) {
      throw new BuiltValueNullFieldError('DevToolsResponse', 'error');
    }
  }

  @override
  DevToolsResponse rebuild(void updates(DevToolsResponseBuilder b)) =>
      (toBuilder()..update(updates)).build();

  @override
  DevToolsResponseBuilder toBuilder() =>
      new DevToolsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DevToolsResponse &&
        success == other.success &&
        error == other.error;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, success.hashCode), error.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DevToolsResponse')
          ..add('success', success)
          ..add('error', error))
        .toString();
  }
}

class DevToolsResponseBuilder
    implements Builder<DevToolsResponse, DevToolsResponseBuilder> {
  _$DevToolsResponse _$v;

  bool _success;
  bool get success => _$this._success;
  set success(bool success) => _$this._success = success;

  String _error;
  String get error => _$this._error;
  set error(String error) => _$this._error = error;

  DevToolsResponseBuilder();

  DevToolsResponseBuilder get _$this {
    if (_$v != null) {
      _success = _$v.success;
      _error = _$v.error;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DevToolsResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$DevToolsResponse;
  }

  @override
  void update(void updates(DevToolsResponseBuilder b)) {
    if (updates != null) updates(this);
  }

  @override
  _$DevToolsResponse build() {
    final _$result =
        _$v ?? new _$DevToolsResponse._(success: success, error: error);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
