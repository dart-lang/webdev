// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'devtools_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<DevToolsRequest> _$devToolsRequestSerializer =
    new _$DevToolsRequestSerializer();

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
      'url',
      serializers.serialize(object.url, specifiedType: const FullType(String)),
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
        case 'url':
          result.url = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$DevToolsRequest extends DevToolsRequest {
  @override
  final String url;

  factory _$DevToolsRequest([void updates(DevToolsRequestBuilder b)]) =>
      (new DevToolsRequestBuilder()..update(updates)).build();

  _$DevToolsRequest._({this.url}) : super._() {
    if (url == null) {
      throw new BuiltValueNullFieldError('DevToolsRequest', 'url');
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
    return other is DevToolsRequest && url == other.url;
  }

  @override
  int get hashCode {
    return $jf($jc(0, url.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DevToolsRequest')..add('url', url))
        .toString();
  }
}

class DevToolsRequestBuilder
    implements Builder<DevToolsRequest, DevToolsRequestBuilder> {
  _$DevToolsRequest _$v;

  String _url;
  String get url => _$this._url;
  set url(String url) => _$this._url = url;

  DevToolsRequestBuilder();

  DevToolsRequestBuilder get _$this {
    if (_$v != null) {
      _url = _$v.url;
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
    final _$result = _$v ?? new _$DevToolsRequest._(url: url);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
