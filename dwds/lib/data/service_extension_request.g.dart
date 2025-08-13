// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_extension_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ServiceExtensionRequest> _$serviceExtensionRequestSerializer =
    _$ServiceExtensionRequestSerializer();

class _$ServiceExtensionRequestSerializer
    implements StructuredSerializer<ServiceExtensionRequest> {
  @override
  final Iterable<Type> types = const [
    ServiceExtensionRequest,
    _$ServiceExtensionRequest,
  ];
  @override
  final String wireName = 'ServiceExtensionRequest';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    ServiceExtensionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
      'method',
      serializers.serialize(
        object.method,
        specifiedType: const FullType(String),
      ),
      'argsJson',
      serializers.serialize(
        object.argsJson,
        specifiedType: const FullType(String),
      ),
    ];

    return result;
  }

  @override
  ServiceExtensionRequest deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServiceExtensionRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'id':
          result.id =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )!
                  as String;
          break;
        case 'method':
          result.method =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )!
                  as String;
          break;
        case 'argsJson':
          result.argsJson =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )!
                  as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ServiceExtensionRequest extends ServiceExtensionRequest {
  @override
  final String id;
  @override
  final String method;
  @override
  final String argsJson;

  factory _$ServiceExtensionRequest([
    void Function(ServiceExtensionRequestBuilder)? updates,
  ]) => (ServiceExtensionRequestBuilder()..update(updates))._build();

  _$ServiceExtensionRequest._({
    required this.id,
    required this.method,
    required this.argsJson,
  }) : super._();
  @override
  ServiceExtensionRequest rebuild(
    void Function(ServiceExtensionRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ServiceExtensionRequestBuilder toBuilder() =>
      ServiceExtensionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServiceExtensionRequest &&
        id == other.id &&
        method == other.method &&
        argsJson == other.argsJson;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, method.hashCode);
    _$hash = $jc(_$hash, argsJson.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServiceExtensionRequest')
          ..add('id', id)
          ..add('method', method)
          ..add('argsJson', argsJson))
        .toString();
  }
}

class ServiceExtensionRequestBuilder
    implements
        Builder<ServiceExtensionRequest, ServiceExtensionRequestBuilder> {
  _$ServiceExtensionRequest? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _method;
  String? get method => _$this._method;
  set method(String? method) => _$this._method = method;

  String? _argsJson;
  String? get argsJson => _$this._argsJson;
  set argsJson(String? argsJson) => _$this._argsJson = argsJson;

  ServiceExtensionRequestBuilder();

  ServiceExtensionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _method = $v.method;
      _argsJson = $v.argsJson;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServiceExtensionRequest other) {
    _$v = other as _$ServiceExtensionRequest;
  }

  @override
  void update(void Function(ServiceExtensionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServiceExtensionRequest build() => _build();

  _$ServiceExtensionRequest _build() {
    final _$result =
        _$v ??
        _$ServiceExtensionRequest._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'ServiceExtensionRequest',
            'id',
          ),
          method: BuiltValueNullFieldError.checkNotNull(
            method,
            r'ServiceExtensionRequest',
            'method',
          ),
          argsJson: BuiltValueNullFieldError.checkNotNull(
            argsJson,
            r'ServiceExtensionRequest',
            'argsJson',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
