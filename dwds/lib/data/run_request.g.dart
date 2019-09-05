// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<RunRequest> _$runRequestSerializer = new _$RunRequestSerializer();
Serializer<RunResponse> _$runResponseSerializer = new _$RunResponseSerializer();

class _$RunRequestSerializer implements StructuredSerializer<RunRequest> {
  @override
  final Iterable<Type> types = const [RunRequest, _$RunRequest];
  @override
  final String wireName = 'RunRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, RunRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    return <Object>[];
  }

  @override
  RunRequest deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    return new RunRequestBuilder().build();
  }
}

class _$RunResponseSerializer implements StructuredSerializer<RunResponse> {
  @override
  final Iterable<Type> types = const [RunResponse, _$RunResponse];
  @override
  final String wireName = 'RunResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, RunResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'appId',
      serializers.serialize(object.appId,
          specifiedType: const FullType(String)),
      'instanceId',
      serializers.serialize(object.instanceId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  RunResponse deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new RunResponseBuilder();

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
        case 'instanceId':
          result.instanceId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$RunRequest extends RunRequest {
  factory _$RunRequest([void Function(RunRequestBuilder) updates]) =>
      (new RunRequestBuilder()..update(updates)).build();

  _$RunRequest._() : super._();

  @override
  RunRequest rebuild(void Function(RunRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RunRequestBuilder toBuilder() => new RunRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RunRequest;
  }

  @override
  int get hashCode {
    return 248087772;
  }

  @override
  String toString() {
    return newBuiltValueToStringHelper('RunRequest').toString();
  }
}

class RunRequestBuilder implements Builder<RunRequest, RunRequestBuilder> {
  _$RunRequest _$v;

  RunRequestBuilder();

  @override
  void replace(RunRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$RunRequest;
  }

  @override
  void update(void Function(RunRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$RunRequest build() {
    final _$result = _$v ?? new _$RunRequest._();
    replace(_$result);
    return _$result;
  }
}

class _$RunResponse extends RunResponse {
  @override
  final String appId;
  @override
  final String instanceId;

  factory _$RunResponse([void Function(RunResponseBuilder) updates]) =>
      (new RunResponseBuilder()..update(updates)).build();

  _$RunResponse._({this.appId, this.instanceId}) : super._() {
    if (appId == null) {
      throw new BuiltValueNullFieldError('RunResponse', 'appId');
    }
    if (instanceId == null) {
      throw new BuiltValueNullFieldError('RunResponse', 'instanceId');
    }
  }

  @override
  RunResponse rebuild(void Function(RunResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RunResponseBuilder toBuilder() => new RunResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RunResponse &&
        appId == other.appId &&
        instanceId == other.instanceId;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, appId.hashCode), instanceId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('RunResponse')
          ..add('appId', appId)
          ..add('instanceId', instanceId))
        .toString();
  }
}

class RunResponseBuilder implements Builder<RunResponse, RunResponseBuilder> {
  _$RunResponse _$v;

  String _appId;
  String get appId => _$this._appId;
  set appId(String appId) => _$this._appId = appId;

  String _instanceId;
  String get instanceId => _$this._instanceId;
  set instanceId(String instanceId) => _$this._instanceId = instanceId;

  RunResponseBuilder();

  RunResponseBuilder get _$this {
    if (_$v != null) {
      _appId = _$v.appId;
      _instanceId = _$v.instanceId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RunResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$RunResponse;
  }

  @override
  void update(void Function(RunResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$RunResponse build() {
    final _$result =
        _$v ?? new _$RunResponse._(appId: appId, instanceId: instanceId);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
