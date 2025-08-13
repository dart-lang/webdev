// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_extension_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ServiceExtensionResponse> _$serviceExtensionResponseSerializer =
    _$ServiceExtensionResponseSerializer();

class _$ServiceExtensionResponseSerializer
    implements StructuredSerializer<ServiceExtensionResponse> {
  @override
  final Iterable<Type> types = const [
    ServiceExtensionResponse,
    _$ServiceExtensionResponse,
  ];
  @override
  final String wireName = 'ServiceExtensionResponse';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    ServiceExtensionResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
      'success',
      serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      ),
    ];
    Object? value;
    value = object.resultJson;
    if (value != null) {
      result
        ..add('resultJson')
        ..add(
          serializers.serialize(value, specifiedType: const FullType(String)),
        );
    }
    value = object.errorCode;
    if (value != null) {
      result
        ..add('errorCode')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
    }
    value = object.errorMessage;
    if (value != null) {
      result
        ..add('errorMessage')
        ..add(
          serializers.serialize(value, specifiedType: const FullType(String)),
        );
    }
    return result;
  }

  @override
  ServiceExtensionResponse deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServiceExtensionResponseBuilder();

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
        case 'resultJson':
          result.resultJson =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )
                  as String?;
          break;
        case 'success':
          result.success =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(bool),
                  )!
                  as bool;
          break;
        case 'errorCode':
          result.errorCode =
              serializers.deserialize(value, specifiedType: const FullType(int))
                  as int?;
          break;
        case 'errorMessage':
          result.errorMessage =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )
                  as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$ServiceExtensionResponse extends ServiceExtensionResponse {
  @override
  final String id;
  @override
  final String? resultJson;
  @override
  final bool success;
  @override
  final int? errorCode;
  @override
  final String? errorMessage;

  factory _$ServiceExtensionResponse([
    void Function(ServiceExtensionResponseBuilder)? updates,
  ]) => (ServiceExtensionResponseBuilder()..update(updates))._build();

  _$ServiceExtensionResponse._({
    required this.id,
    this.resultJson,
    required this.success,
    this.errorCode,
    this.errorMessage,
  }) : super._();
  @override
  ServiceExtensionResponse rebuild(
    void Function(ServiceExtensionResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ServiceExtensionResponseBuilder toBuilder() =>
      ServiceExtensionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServiceExtensionResponse &&
        id == other.id &&
        resultJson == other.resultJson &&
        success == other.success &&
        errorCode == other.errorCode &&
        errorMessage == other.errorMessage;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, resultJson.hashCode);
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, errorCode.hashCode);
    _$hash = $jc(_$hash, errorMessage.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServiceExtensionResponse')
          ..add('id', id)
          ..add('resultJson', resultJson)
          ..add('success', success)
          ..add('errorCode', errorCode)
          ..add('errorMessage', errorMessage))
        .toString();
  }
}

class ServiceExtensionResponseBuilder
    implements
        Builder<ServiceExtensionResponse, ServiceExtensionResponseBuilder> {
  _$ServiceExtensionResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _resultJson;
  String? get resultJson => _$this._resultJson;
  set resultJson(String? resultJson) => _$this._resultJson = resultJson;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  int? _errorCode;
  int? get errorCode => _$this._errorCode;
  set errorCode(int? errorCode) => _$this._errorCode = errorCode;

  String? _errorMessage;
  String? get errorMessage => _$this._errorMessage;
  set errorMessage(String? errorMessage) => _$this._errorMessage = errorMessage;

  ServiceExtensionResponseBuilder();

  ServiceExtensionResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _resultJson = $v.resultJson;
      _success = $v.success;
      _errorCode = $v.errorCode;
      _errorMessage = $v.errorMessage;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServiceExtensionResponse other) {
    _$v = other as _$ServiceExtensionResponse;
  }

  @override
  void update(void Function(ServiceExtensionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServiceExtensionResponse build() => _build();

  _$ServiceExtensionResponse _build() {
    final _$result =
        _$v ??
        _$ServiceExtensionResponse._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'ServiceExtensionResponse',
            'id',
          ),
          resultJson: resultJson,
          success: BuiltValueNullFieldError.checkNotNull(
            success,
            r'ServiceExtensionResponse',
            'success',
          ),
          errorCode: errorCode,
          errorMessage: errorMessage,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
