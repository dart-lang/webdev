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
  Iterable serialize(Serializers serializers, ConnectRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'appId',
      serializers.serialize(object.appId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  ConnectRequest deserialize(Serializers serializers, Iterable serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ConnectRequestBuilder();

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

class _$ConnectRequest extends ConnectRequest {
  @override
  final String appId;

  factory _$ConnectRequest([void updates(ConnectRequestBuilder b)]) =>
      (new ConnectRequestBuilder()..update(updates)).build();

  _$ConnectRequest._({this.appId}) : super._() {
    if (appId == null) {
      throw new BuiltValueNullFieldError('ConnectRequest', 'appId');
    }
  }

  @override
  ConnectRequest rebuild(void updates(ConnectRequestBuilder b)) =>
      (toBuilder()..update(updates)).build();

  @override
  ConnectRequestBuilder toBuilder() =>
      new ConnectRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ConnectRequest && appId == other.appId;
  }

  @override
  int get hashCode {
    return $jf($jc(0, appId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ConnectRequest')..add('appId', appId))
        .toString();
  }
}

class ConnectRequestBuilder
    implements Builder<ConnectRequest, ConnectRequestBuilder> {
  _$ConnectRequest _$v;

  String _appId;
  String get appId => _$this._appId;
  set appId(String appId) => _$this._appId = appId;

  ConnectRequestBuilder();

  ConnectRequestBuilder get _$this {
    if (_$v != null) {
      _appId = _$v.appId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ConnectRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ConnectRequest;
  }

  @override
  void update(void updates(ConnectRequestBuilder b)) {
    if (updates != null) updates(this);
  }

  @override
  _$ConnectRequest build() {
    final _$result = _$v ?? new _$ConnectRequest._(appId: appId);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
