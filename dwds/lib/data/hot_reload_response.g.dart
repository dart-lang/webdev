// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hot_reload_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<HotReloadResponse> _$hotReloadResponseSerializer =
    _$HotReloadResponseSerializer();

class _$HotReloadResponseSerializer
    implements StructuredSerializer<HotReloadResponse> {
  @override
  final Iterable<Type> types = const [HotReloadResponse, _$HotReloadResponse];
  @override
  final String wireName = 'HotReloadResponse';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    HotReloadResponse object, {
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
    value = object.errorMessage;
    if (value != null) {
      result
        ..add('error')
        ..add(
          serializers.serialize(value, specifiedType: const FullType(String)),
        );
    }
    return result;
  }

  @override
  HotReloadResponse deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HotReloadResponseBuilder();

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
        case 'success':
          result.success =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(bool),
                  )!
                  as bool;
          break;
        case 'error':
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

class _$HotReloadResponse extends HotReloadResponse {
  @override
  final String id;
  @override
  final bool success;
  @override
  final String? errorMessage;

  factory _$HotReloadResponse([
    void Function(HotReloadResponseBuilder)? updates,
  ]) => (HotReloadResponseBuilder()..update(updates))._build();

  _$HotReloadResponse._({
    required this.id,
    required this.success,
    this.errorMessage,
  }) : super._();
  @override
  HotReloadResponse rebuild(void Function(HotReloadResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HotReloadResponseBuilder toBuilder() =>
      HotReloadResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HotReloadResponse &&
        id == other.id &&
        success == other.success &&
        errorMessage == other.errorMessage;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, errorMessage.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HotReloadResponse')
          ..add('id', id)
          ..add('success', success)
          ..add('errorMessage', errorMessage))
        .toString();
  }
}

class HotReloadResponseBuilder
    implements Builder<HotReloadResponse, HotReloadResponseBuilder> {
  _$HotReloadResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  String? _errorMessage;
  String? get errorMessage => _$this._errorMessage;
  set errorMessage(String? errorMessage) => _$this._errorMessage = errorMessage;

  HotReloadResponseBuilder();

  HotReloadResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _success = $v.success;
      _errorMessage = $v.errorMessage;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HotReloadResponse other) {
    _$v = other as _$HotReloadResponse;
  }

  @override
  void update(void Function(HotReloadResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HotReloadResponse build() => _build();

  _$HotReloadResponse _build() {
    final _$result =
        _$v ??
        _$HotReloadResponse._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'HotReloadResponse',
            'id',
          ),
          success: BuiltValueNullFieldError.checkNotNull(
            success,
            r'HotReloadResponse',
            'success',
          ),
          errorMessage: errorMessage,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
